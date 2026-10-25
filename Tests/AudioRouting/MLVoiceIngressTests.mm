// Verify transport/audio routing without sockets, microphones or real Opus decoding.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "MLClient.h"
#include <memory>
#include <atomic>
struct MLNetworkState;
@interface MLConnection (IngressTests)
- (std::shared_ptr<MLNetworkState>)networkState;
- (void)queueReceivedVoice:(NSData *)data session:(NSUInteger)session sequence:(uint64_t)sequence talkState:(MLTalkState)talk terminator:(BOOL)terminator state:(const std::shared_ptr<MLNetworkState> &)state;
@end
static MLAudio *ingressAudio;
static dispatch_semaphore_t decodedSignal;
static std::atomic_uint64_t decodedCount, activityCount;
static std::atomic_bool decodedOnMain, activityOffMain;
static IMP originalActivity;
static id FixtureAudio(id object,SEL command){return ingressAudio;}
static void NoNetwork(id object,SEL command,std::shared_ptr<MLNetworkState> state,NSString *hostname,NSArray *identity,NSData *accepted){}
static void DecodeProbe(id object,SEL command,NSData *data,NSUInteger session,uint64_t sequence,BOOL terminator){
    if(NSThread.isMainThread)decodedOnMain=true;
    ++decodedCount;dispatch_semaphore_signal(decodedSignal);
}
static void ActivityProbe(id object,SEL command,NSUInteger session,MLTalkState state,BOOL hasAudio,BOOL terminator){
    if(!NSThread.isMainThread)activityOffMain=true;
    ++activityCount;((void (*)(id,SEL,NSUInteger,MLTalkState,BOOL,BOOL))originalActivity)(object,command,session,state,hasAudio,terminator);
}
static void Check(BOOL condition,NSString *message){if(!condition)@throw [NSException exceptionWithName:@"VoiceIngressFailure" reason:message userInfo:nil];}
static void Wait(BOOL (^ready)(void)){
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:3];
    while(!ready() && deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
    Check(ready(),@"Timed out waiting for a speaking update");
}
static void SetRunning(MLAudio *audio,BOOL value){
    Ivar field=class_getInstanceVariable(MLAudio.class,"_running");
    reinterpret_cast<std::atomic_bool *>(reinterpret_cast<uint8_t *>((__bridge void *)audio)+ivar_getOffset(field))->store(value);
}
static NSUInteger Pending(MLAudio *audio){
    Ivar field=class_getInstanceVariable(MLAudio.class,"_queuedPlaybackPackets");
    return reinterpret_cast<std::atomic_size_t *>(reinterpret_cast<uint8_t *>((__bridge void *)audio)+ivar_getOffset(field))->load();
}
void MLVoiceIngressTests(void (^record)(NSString *)){
    Method shared=class_getClassMethod(MLAudio.class,@selector(sharedAudio));IMP originalShared=method_setImplementation(shared,(IMP)FixtureAudio);
    Method run=class_getInstanceMethod(MLConnection.class,NSSelectorFromString(@"run:hostname:identity:accepted:"));IMP originalRun=method_setImplementation(run,(IMP)NoNetwork);
    Method decode=class_getInstanceMethod(MLAudio.class,NSSelectorFromString(@"playOpusFrame:session:sequence:terminator:"));IMP originalDecode=method_setImplementation(decode,(IMP)DecodeProbe);
    Method activity=class_getInstanceMethod(MLServerModel.class,NSSelectorFromString(@"receivedVoiceForSession:talkState:hasAudio:terminator:"));originalActivity=method_setImplementation(activity,(IMP)ActivityProbe);
    ingressAudio=[MLAudio new];MLAudio *audio=ingressAudio;
    MLConnection *connection=[MLConnection new];MLServerModel *model=[[MLServerModel alloc]initWithConnection:connection];
    dispatch_queue_t network=dispatch_queue_create("mumble.ingress.test",DISPATCH_QUEUE_SERIAL);
    decodedSignal=dispatch_semaphore_create(0);decodedCount=0;activityCount=0;decodedOnMain=false;activityOffMain=false;
    @try{
        [connection connectToHost:@"voice-fixture.invalid" port:64738];
        MLUser *user=[MLUser new];user.session=42;user.userName=@"Fixture";[user setValue:model forKey:@"audioModel"];
        [[model valueForKey:@"_users"]setObject:user forKey:@42];
        [audio setMainConnectionForAudio:connection];[audio copyAudioOutputMixerDebugInfo];SetRunning(audio,YES);
        auto state=[connection networkState];NSData *packet=[NSData dataWithBytes:"x" length:1];
        dispatch_async(network,^{[connection queueReceivedVoice:packet session:42 sequence:0 talkState:MLTalkStateTalking terminator:NO state:state];});
        // Deliberately do not service the main run loop until audio has arrived.
        Check(dispatch_semaphore_wait(decodedSignal,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0 && !decodedOnMain,@"Incoming voice waits for the UI thread before reaching DSP");
        Check(user.talkState==MLTalkStatePassive,@"Speaking updates bypassed the UI queue");
        Wait(^BOOL{return user.talkState==MLTalkStateTalking;});
        uint64_t updates=activityCount;
        dispatch_sync(network,^{for(uint64_t i=1;i<=100;i++)[connection queueReceivedVoice:packet session:42 sequence:i talkState:MLTalkStateTalking terminator:i==100 state:state];});
        [audio copyAudioOutputMixerDebugInfo];Wait(^BOOL{return activityCount>updates;});
        Check(activityCount==updates+1 && !activityOffMain,@"A packet burst floods the UI or updates the model off main thread");
        record(@"incoming voice reaches DSP while UI is blocked; speaking updates coalesce on main thread");
        dispatch_queue_t queue=(dispatch_queue_t)[audio valueForKey:@"_queue"];
        dispatch_semaphore_t gate=dispatch_semaphore_create(0),entered=dispatch_semaphore_create(0);
        dispatch_async(queue,^{dispatch_semaphore_signal(entered);dispatch_semaphore_wait(gate,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC));});
        Check(dispatch_semaphore_wait(entered,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0,@"Audio queue did not enter the mute fixture");
        uint64_t before=decodedCount;
        @try{
            dispatch_sync(network,^{[connection queueReceivedVoice:packet session:42 sequence:101 talkState:MLTalkStateTalking terminator:NO state:state];});
            user.localMuted=YES;user.localMuted=NO;
            dispatch_semaphore_signal(gate);[audio copyAudioOutputMixerDebugInfo];
            Check(decodedCount==before,@"Unmuting releases audio queued before local mute");
        }@finally{dispatch_semaphore_signal(gate);}
        record(@"per-user mute snapshots reject queued audio even after a quick unmute");
        gate=dispatch_semaphore_create(0);entered=dispatch_semaphore_create(0);
        dispatch_async(queue,^{dispatch_semaphore_signal(entered);dispatch_semaphore_wait(gate,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC));});
        Check(dispatch_semaphore_wait(entered,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0,@"Audio queue did not enter burst fixture");
        before=decodedCount;
        @try{
            dispatch_sync(network,^{for(uint64_t i=102;i<502;i++)[connection queueReceivedVoice:packet session:42 sequence:i talkState:MLTalkStateTalking terminator:NO state:state];});
            Check(Pending(audio)>0 && Pending(audio)<=128,@"Busy DSP accepts an unbounded packet backlog");
            dispatch_semaphore_signal(gate);[audio copyAudioOutputMixerDebugInfo];
            Check(decodedCount-before<=128,@"Playback exceeded its bounded ingress queue");
        }@finally{dispatch_semaphore_signal(gate);}
        gate=dispatch_semaphore_create(0);entered=dispatch_semaphore_create(0);
        dispatch_async(queue,^{dispatch_semaphore_signal(entered);dispatch_semaphore_wait(gate,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC));});
        Check(dispatch_semaphore_wait(entered,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0,@"Audio queue did not enter reconnect fixture");
        before=decodedCount;
        @try{
            dispatch_sync(network,^{[connection queueReceivedVoice:packet session:42 sequence:503 talkState:MLTalkStateTalking terminator:NO state:state];});
            [connection connectToHost:@"next-fixture.invalid" port:64738];[audio setMainConnectionForAudio:connection];
            dispatch_semaphore_signal(gate);[audio copyAudioOutputMixerDebugInfo];
            Check(decodedCount==before,@"A previous connection's queued packet plays after reconnect");
            dispatch_sync(network,^{[connection queueReceivedVoice:packet session:42 sequence:504 talkState:MLTalkStateTalking terminator:NO state:state];});
            [audio copyAudioOutputMixerDebugInfo];Check(decodedCount==before,@"A cancelled transport can enqueue new voice after reconnect");
            auto current=[connection networkState];
            dispatch_sync(network,^{[connection queueReceivedVoice:packet session:42 sequence:0 talkState:MLTalkStateTalking terminator:NO state:current];});
            [audio copyAudioOutputMixerDebugInfo];Check(decodedCount==before+1,@"The current connection cannot resume playback after reconnect");
        }@finally{dispatch_semaphore_signal(gate);}
        record(@"bounded voice ingress and reconnect generations discard stale playback");
    }@finally{
        [connection disconnect];SetRunning(audio,NO);[audio stop];
        dispatch_sync((dispatch_queue_t)[connection valueForKey:@"_worker"],^{});
        method_setImplementation(shared,originalShared);method_setImplementation(run,originalRun);method_setImplementation(decode,originalDecode);method_setImplementation(activity,originalActivity);ingressAudio=nil;decodedSignal=nil;
    }
}

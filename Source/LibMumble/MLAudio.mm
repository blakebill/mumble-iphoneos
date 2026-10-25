#import "MLInternal.hpp"
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#include <mumble/Opus.hpp>
#include <speex/speex_preprocess.h>
#include <map>
#include <vector>
#include <mutex>
#include <atomic>
#include <array>
#include <cmath>
#include "MLCaptureBufferQueue.hpp"

NSString *MLAudioDidRestartNotification=@"MLAudioDidRestartNotification";

@interface MLPlayback : NSObject {
@public
    std::unique_ptr<mumble::Opus::Decoder> decoder;
    uint64_t nextSequence;
    NSUInteger generation;
    double queuedSeconds;
}
@property(nonatomic,strong) AVAudioPlayerNode *player;
@property(nonatomic) NSTimeInterval lastPacket;
- (AVAudioPCMBuffer *)bufferWithFormat:(AVAudioFormat *)format;
- (void)recycleBuffer:(AVAudioPCMBuffer *)buffer;
@end
@implementation MLPlayback {
    NSMutableArray<AVAudioPCMBuffer *> *_freeBuffers;
}
- (instancetype)init { if ((self=[super init])) { decoder=std::make_unique<mumble::Opus::Decoder>(1); decoder->init(); _freeBuffers=[NSMutableArray array]; } return self; }
- (AVAudioPCMBuffer *)bufferWithFormat:(AVAudioFormat *)format {
    AVAudioPCMBuffer *buffer=_freeBuffers.lastObject;
    if (buffer) [_freeBuffers removeLastObject];
    else buffer=[[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:5760];
    return buffer;
}
- (void)recycleBuffer:(AVAudioPCMBuffer *)buffer {
    if (_freeBuffers.count<24) [_freeBuffers addObject:buffer];
}
@end

@implementation MLAudio {
    AVAudioEngine *_engine;
    AVAudioConverter *_converter;
    AVAudioPCMBuffer *_convertedInput;
    AVAudioFormat *_format;
    AVAudioPlayerNode *_sidetone;
    dispatch_queue_t _queue, _sessionQueue;
    NSMutableDictionary<NSNumber *,MLPlayback *> *_players;
    __weak MLConnection *_connection;
    std::unique_ptr<mumble::Opus::Encoder> _encoder;
    SpeexPreprocessState *_preprocessor;
    std::vector<int16_t> _pending;
    mumble::Buf _encodedBuffer;
    MLAudioSettings _settings;
    std::mutex _settingsMutex;
    std::atomic_bool _running, _forced, _localMuted, _localDeafened;
    std::atomic_bool _captureNeeded;
    std::atomic_size_t _meterUsers;
    std::atomic_uint64_t _tapCount, _processedCount;
    std::atomic_bool _captureWarmup;
    std::atomic_bool _meterOwnsCapture;
    std::atomic<float> _peak, _speech;
    std::atomic_uint32_t _bandwidthLimit;
    uint64_t _sequence;
    BOOL _transmitting, _wantRunning;
    // Lifecycle state is confined to the main thread. Only one session operation may be in flight.
    BOOL _sessionTransition, _sessionActive, _permissionRequested, _interrupted, _notifyRestart, _tapInstalled;
    NSUInteger _lifecycleGeneration;
    std::atomic_size_t _generation;
    dispatch_source_t _cleanupTimer;
    dispatch_source_t _captureSource;
    NSTimer *_engineRetryTimer;
    NSTimer *_captureMonitorTimer;
    uint64_t _lastTapSeen, _lastProcessedSeen;
    uint64_t _processingLogBaseline;
    NSTimeInterval _tapChangedAt, _processedChangedAt;
    NSUInteger _engineRetryCount;
    BOOL _engineRecoveryInFlight;
    NSUInteger _engineRecoveryCount;
    NSTimeInterval _engineRecoveryWindow;
}
+ (instancetype)sharedAudio { static MLAudio *audio; static dispatch_once_t once; dispatch_once(&once, ^{ audio=[self new]; }); return audio; }
- (instancetype)init {
    if ((self=[super init])) {
        _queue=dispatch_queue_create("info.mumble.libmumble.audio",dispatch_queue_attr_make_with_autorelease_frequency(DISPATCH_QUEUE_SERIAL,DISPATCH_AUTORELEASE_FREQUENCY_WORK_ITEM));
        _sessionQueue=dispatch_queue_create("info.mumble.libmumble.audio-session",DISPATCH_QUEUE_SERIAL);
        _players=[NSMutableDictionary dictionary];
        _settings={}; _settings.quality=40000; _settings.audioPerPacket=2;
        _settings.volume=1; _settings.micBoost=1; _settings.vadMin=.65; _settings.vadMax=.75;
        _settings.noiseSuppression=-42; _settings.amplification=20; _peak=-96;
        _captureNeeded=true; _pending.reserve(8192); _encodedBuffer.resize(4096);
        NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270000
        if (@available(iOS 27.0, *)) {
            [center addObserver:self selector:@selector(sessionBecameInactive:) name:AVAudioSessionDidBecomeInactiveNotification object:nil];
            [center addObserver:self selector:@selector(sessionMayResume:) name:AVAudioSessionResumptionRecommendationNotification object:nil];
        } else
#endif
        [center addObserver:self selector:@selector(interrupted:) name:AVAudioSessionInterruptionNotification object:nil];
        [center addObserver:self selector:@selector(routeChanged:) name:AVAudioSessionRouteChangeNotification object:nil];
        [center addObserver:self selector:@selector(mediaReset:) name:AVAudioSessionMediaServicesWereResetNotification object:nil];
        [center addObserver:self selector:@selector(engineConfigurationChanged:) name:AVAudioEngineConfigurationChangeNotification object:nil];
    }
    return self;
}
- (BOOL)isRunning { return _running && _engine.isRunning; }
- (BOOL)forceTransmit { return _forced; }
- (void)setForceTransmit:(BOOL)value {
    BOOL wasForced=_forced.exchange(value); [self updateCaptureDemand];
    if (value && !wasForced) [self requestCaptureRecovery];
}
- (MLAudioSettings)settings { std::lock_guard guard(_settingsMutex); return _settings; }
- (MLTransmitType)transmitType { return self.settings.transmitType; }
- (void)readAudioSettings:(MLAudioSettings *)settings { if (settings) *settings=self.settings; }
- (void)updateAudioSettings:(MLAudioSettings *)settings {
    if (!settings) return;
    MLAudioSettings value=*settings;
    value.quality=std::clamp(value.quality,6000,128000);
    value.audioPerPacket=value.audioPerPacket<=1?1:value.audioPerPacket<=2?2:value.audioPerPacket<=4?4:6;
    value.volume=std::clamp(value.volume,0.f,2.f); value.micBoost=std::clamp(value.micBoost,0.f,2.f);
    // Apple's voice processor owns echo cancellation, noise reduction and AGC.
    value.enableEchoCancellation=value.enablePreprocessor;
    if (value.enablePreprocessor) value.micBoost=1;
    { std::lock_guard guard(_settingsMutex); _settings=value; }
    dispatch_async(_queue, ^{
        MLAudioSettings current=self.settings;
        [self configureActivityDetectorWithSettings:current];
        if (self->_engine) self->_engine.mainMixerNode.outputVolume=current.volume;
    });
    [self updateCaptureDemand];
}
- (BOOL)echoCancellationAvailable { return YES; }
- (float)peakCleanMic { return _peak; }
- (float)speechProbablity { return _speech; }
- (void)setLocalMuted:(BOOL)muted deafened:(BOOL)deafened {
    BOOL wasMuted=_localMuted.exchange(muted), wasDeafened=_localDeafened.exchange(deafened);
    [self updateCaptureDemand];
    if (deafened && !wasDeafened) dispatch_async(_queue, ^{
        if (!self->_localDeafened) return;
        for (MLPlayback *playback in self->_players.allValues) { [playback.player stop]; [self->_engine detachNode:playback.player]; }
        [self->_players removeAllObjects];
        if (self->_cleanupTimer) { dispatch_source_cancel(self->_cleanupTimer); self->_cleanupTimer=nil; }
    });
    if (wasMuted && !muted) [self requestCaptureRecovery];
}
- (void)requestCaptureRecovery {
    dispatch_async(dispatch_get_main_queue(), ^{ [self resumeIfNeeded]; });
}
- (void)resumeIfNeeded {
    NSAssert(NSThread.isMainThread,@"Audio lifecycle runs on the main thread");
    if (!_wantRunning && _meterUsers>0 && UIApplication.sharedApplication.applicationState!=UIApplicationStateBackground) {
        _meterOwnsCapture=true;
        [self start];
    }
    BOOL stalled=[self captureHasStalled];
    if (!_wantRunning || ([self isRunning] && !stalled)) return;
    if ([self.delegate respondsToSelector:@selector(audioShouldBeRunning:)] && ![self.delegate audioShouldBeRunning:self]) return;
    // An interruption began notification is not guaranteed to have an ended pair.
    // Foreground return or an explicit capture action may request one activation;
    // the system still decides whether higher-priority audio permits it.
    _interrupted=NO; _engineRetryCount=0; _engineRecoveryCount=0;
    if (stalled) [self checkCaptureHealth];
    else if (_engine && !_sessionTransition) [self recoverStoppedEngine];
    else [self start];
}
- (void)beginMetering { ++_meterUsers; [self updateCaptureDemand]; [self requestCaptureRecovery]; }
- (void)endMetering {
    if (_meterUsers) --_meterUsers;
    [self updateCaptureDemand];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_meterUsers && self->_meterOwnsCapture.exchange(false)) [self stop];
    });
}
- (void)updateCaptureDemand {
    MLAudioSettings settings=self.settings;
    BOOL mayTransmit=!_localMuted && (settings.transmitType!=MLTransmitTypeToggle || _forced);
    BOOL needed=mayTransmit || _meterUsers>0;
    if (!_captureNeeded.exchange(needed) && needed) _captureWarmup=true;
    if (!mayTransmit) dispatch_async(_queue, ^{
        MLAudioSettings current=self.settings;
        if (!self->_localMuted && (current.transmitType!=MLTransmitTypeToggle || self->_forced)) return;
        MLConnection *connection=self->_connection;
        if (self->_transmitting) {
            [connection sendOpus:[NSData data] sequence:self->_sequence terminator:YES];
            dispatch_async(dispatch_get_main_queue(), ^{ [connection.model setTalkState:MLTalkStatePassive forSession:connection.model.connectedUser.session]; });
        }
        self->_transmitting=NO; self->_pending.clear(); self->_peak=-96; self->_speech=0;
    });
}
- (void)setBandwidthLimit:(uint32_t)bandwidth { _bandwidthLimit=bandwidth; }
- (void)setMainConnectionForAudio:(MLConnection *)connection {
    if (connection) _meterOwnsCapture=false;
    dispatch_async(_queue, ^{ self->_connection=connection; self->_pending.clear(); self->_sequence=0; self->_transmitting=NO; self->_forced=false;
        if (self->_engine) self->_engine.mainMixerNode.outputVolume=self.settings.volume;
        for (MLPlayback *playback in self->_players.allValues) { [playback.player stop]; [self->_engine detachNode:playback.player]; }
        [self->_players removeAllObjects];
        [self updateCaptureDemand];
    });
}
- (void)start {
    NSAssert(NSThread.isMainThread,@"Audio lifecycle runs on the main thread");
    if (!_wantRunning) { _engineRetryCount=0; _engineRecoveryCount=0; _engineRecoveryWindow=0; }
    _wantRunning=YES;
    if (_running || _sessionTransition || _interrupted || _engineRetryTimer || _engineRecoveryInFlight) return;
    if (AVAudioApplication.sharedInstance.recordPermission==AVAudioApplicationRecordPermissionUndetermined) {
        if (_permissionRequested) return;
        _permissionRequested=YES;
        [AVAudioApplication requestRecordPermissionWithCompletionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_permissionRequested=NO;
                if (granted && self->_wantRunning) [self start];
            });
        }]; return;
    }
    if (AVAudioApplication.sharedInstance.recordPermission!=AVAudioApplicationRecordPermissionGranted) return;
    MLAudioSettings settings=self.settings;
    NSUInteger generation=_lifecycleGeneration;
    _sessionTransition=YES;
    dispatch_async(_sessionQueue, ^{
        AVAudioSession *session=AVAudioSession.sharedInstance;
        NSError *error=nil;
        // A live conversation must coexist with foreground video/music instead
        // of participating in the last-activated exclusive playback session.
        AVAudioSessionCategoryOptions options=AVAudioSessionCategoryOptionAllowBluetoothHFP | AVAudioSessionCategoryOptionMixWithOthers;
        if (!settings.preferReceiverOverSpeaker) options|=AVAudioSessionCategoryOptionDefaultToSpeaker;
        NSString *mode=settings.enablePreprocessor ? AVAudioSessionModeVoiceChat : AVAudioSessionModeDefault;
        if (![session setCategory:AVAudioSessionCategoryPlayAndRecord mode:mode options:options error:&error] ||
            ![session setPreferredSampleRate:48000 error:&error] || ![session setPreferredIOBufferDuration:.01 error:&error]) {
            [self completeActivation:NO error:error generation:generation settings:settings]; return;
        }
        NSError *alertPreferenceError=nil;
        if (![session setPrefersNoInterruptionsFromSystemAlerts:YES error:&alertPreferenceError])
            NSLog(@"Audio alert interruption preference unavailable: %@",alertPreferenceError);
        // The older SDK used by CI and iOS 18–26 use the same serialized background fallback.
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270000
        if (@available(iOS 27.0, *)) {
            [session activateWithOptions:AVAudioSessionActivationOptionNone completionHandler:^(BOOL active, NSError *activationError) {
                [self completeActivation:active error:activationError generation:generation settings:settings];
            }];
            return;
        }
#endif
        BOOL active=[session setActive:YES error:&error];
        [self completeActivation:active error:error generation:generation settings:settings];
    });
}
- (void)completeActivation:(BOOL)active error:(NSError *)error generation:(NSUInteger)generation settings:(MLAudioSettings)settings {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_sessionTransition=NO;
        // A failed activation does not prove a previously active session was released.
        self->_sessionActive=self->_sessionActive || active;
        if (generation!=self->_lifecycleGeneration || !self->_wantRunning || self->_interrupted) {
            if (self->_sessionActive) [self deactivateSession];
            else if (self->_wantRunning && !self->_interrupted) [self start];
            return;
        }
        if (!active) { NSLog(@"Audio session failed: %@",error); return; }
        [self startEngineWithSettings:settings];
    });
}
- (void)deactivateSession {
    NSAssert(NSThread.isMainThread,@"Audio lifecycle runs on the main thread");
    if (_sessionTransition || !_sessionActive) return;
    _sessionTransition=YES;
    void (^completed)(BOOL,NSError *)=^(BOOL inactive,NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_sessionTransition=NO;
            self->_sessionActive=!inactive;
            if (!inactive) NSLog(@"Audio session deactivation failed: %@",error);
            if (self->_wantRunning && !self->_interrupted) [self start];
        });
    };
    dispatch_async(_sessionQueue, ^{
        AVAudioSession *session=AVAudioSession.sharedInstance;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270000
        if (@available(iOS 27.0, *)) {
            [session deactivateWithOptions:AVAudioSessionDeactivationOptionNotifyOthersOnDeactivation completionHandler:completed];
            return;
        }
#endif
        NSError *error=nil;
        BOOL inactive=[session setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&error];
        completed(inactive,error);
    });
}
- (AVAudioEngine *)makeAudioEngine { return [AVAudioEngine new]; }
- (void)startEngineWithSettings:(MLAudioSettings)settings {
    NSError *error=nil;
    _engine=[self makeAudioEngine];
    _engine.autoShutdownEnabled=NO;
    if (![self configureVoiceProcessingForInput:_engine.inputNode settings:settings error:&error]) { [self engineStartupFailed:error]; return; }
    AVAudioFormat *input=[_engine.inputNode outputFormatForBus:0];
    if (input.sampleRate<=0 || !input.channelCount) {
        [self engineStartupFailed:[NSError errorWithDomain:@"MLAudio" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Microphone input format is not ready"}]];
        return;
    }
    _format=[[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32 sampleRate:48000 channels:1 interleaved:NO];
    _converter=[[AVAudioConverter alloc] initFromFormat:input toFormat:_format];
    if (!_converter) {
        [self engineStartupFailed:[NSError errorWithDomain:@"MLAudio" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Audio conversion unavailable"}]];
        return;
    }
    if (settings.enableSideTone && settings.sidetoneVolume>0) {
        _sidetone=[AVAudioPlayerNode new]; [_engine attachNode:_sidetone];
        [_engine connect:_sidetone to:_engine.mainMixerNode format:_format];
    }
    _engine.mainMixerNode.outputVolume=settings.volume;
    dispatch_sync(_queue, ^{ [self prepareEncoderWithSettings:settings]; });
    NSUInteger generation=++_generation;
    uint64_t tapBaseline=_tapCount;
    __weak MLAudio *weakSelf=self;
    auto buffers=std::make_shared<MLCaptureBufferQueue>(input,8192);
    if (!buffers->valid) {
        [self engineStartupFailed:[NSError errorWithDomain:@"MLAudio" code:3 userInfo:@{NSLocalizedDescriptionKey:@"Microphone buffers unavailable"}]];
        return;
    }
    _captureSource=dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD,0,0,_queue);
    dispatch_source_t captureSource=_captureSource;
    dispatch_source_set_event_handler(captureSource, ^{
        MLAudio *audio=weakSelf;
        if (!audio || !audio->_running || generation!=audio->_generation) return;
        // Bound each drain so playback, settings and teardown can share the queue.
        for (size_t count=0;count<MLCaptureBufferQueue::slotCount;++count) {
            if (!audio->_running || generation!=audio->_generation) break;
            auto *slot=buffers->front(); if (!slot) break;
            slot->buffer.frameLength=slot->frames;
            [audio capture:slot->buffer];
            buffers->pop();
        }
        if (buffers->front()) dispatch_source_merge_data(audio->_captureSource,1);
    });
    dispatch_resume(captureSource);
    [_engine.inputNode installTapOnBus:0 bufferSize:480 format:input block:^(AVAudioPCMBuffer *buffer,AVAudioTime *time) {
        MLAudio *audio=weakSelf; if (!audio || generation!=audio->_generation) return;
        // Count callback delivery even when mute/PTT intentionally skips DSP.
        if (audio->_tapCount.fetch_add(1)==tapBaseline) {
            AVAudioFrameCount frames=buffer.frameLength;
            double rate=buffer.format.sampleRate;
            dispatch_async(audio->_queue, ^{
                if (generation==audio->_generation) NSLog(@"Microphone callbacks started: %u frames at %.0f Hz",frames,rate);
            });
        }
        if (!audio->_captureNeeded) return;
        AVAudioFrameCount frames=buffer.frameLength, offset=0;
        const AudioBufferList *inputBuffers=buffer.audioBufferList;
        while (offset<frames) {
            AVAudioFrameCount count=std::min(buffers->capacity,frames-offset);
            if (!buffers->push(*inputBuffers,count,offset)) break;
            offset+=count;
        }
        if (frames) dispatch_source_merge_data(captureSource,1);
    }];
    _tapInstalled=YES;
    [_engine prepare];
    if (![_engine startAndReturnError:&error]) { [self engineStartupFailed:error]; return; }
    _running=true; _engineRetryCount=0; [_sidetone play];
    AVAudioSession *session=AVAudioSession.sharedInstance;
    NSLog(@"Audio started: category=%@, mode=%@, options=%lu, voiceProcessing=%d",session.category,session.mode,(unsigned long)session.categoryOptions,settings.enablePreprocessor);
    [self startCaptureMonitor];
    if (_notifyRestart) {
        _notifyRestart=NO;
        [NSNotificationCenter.defaultCenter postNotificationName:MLAudioDidRestartNotification object:self];
    }
}
- (BOOL)configureVoiceProcessingForInput:(AVAudioInputNode *)input settings:(MLAudioSettings)settings error:(NSError **)error {
    if (!settings.enablePreprocessor) return YES;
    if (![input setVoiceProcessingEnabled:YES error:error]) return NO;
    input.voiceProcessingBypassed=NO;
    input.voiceProcessingAGCEnabled=YES;
    // VoiceIO detects local and remote speech itself. Lower competing media
    // during speech without continuously ducking it throughout the connection.
    input.voiceProcessingOtherAudioDuckingConfiguration = {YES, AVAudioVoiceProcessingOtherAudioDuckingLevelMid};
    return YES;
}
- (void)prepareEncoderWithSettings:(MLAudioSettings)settings {
    _encoder=std::make_unique<mumble::Opus::Encoder>(1);
    _encoder->init(48000,settings.opusForceCELTMode?mumble::Opus::Encoder::Preset::LowDelay:mumble::Opus::Encoder::Preset::VoIP);
    _encoder->setBitrate((uint32_t)settings.quality); _encoder->toggleVBR(true);
    if (_preprocessor) speex_preprocess_state_destroy(_preprocessor);
    _preprocessor=nullptr;
    [self configureActivityDetectorWithSettings:settings];
    // A graph rebuild on the same connection must keep voice sequence numbers.
    _pending.clear(); _transmitting=NO;
    _processingLogBaseline=_processedCount;
}
- (void)configureActivityDetectorWithSettings:(MLAudioSettings)settings {
    BOOL required=settings.enablePreprocessor && settings.vadKind==MLVADKindSignalToNoise;
    if (!required) {
        if (_preprocessor) speex_preprocess_state_destroy(_preprocessor);
        _preprocessor=nullptr; _speech=0;
        return;
    }
    if (_preprocessor) return;
    // The optional legacy SNR detector analyses a copy; it never processes
    // the PCM sent to Opus. Do not apply a second denoiser or AGC to VoiceIO.
    if (required) {
        _preprocessor=speex_preprocess_state_init(480,48000);
        if (_preprocessor) {
            int disabled=0;
            speex_preprocess_ctl(_preprocessor,SPEEX_PREPROCESS_SET_DENOISE,&disabled);
            speex_preprocess_ctl(_preprocessor,SPEEX_PREPROCESS_SET_AGC,&disabled);
        }
    }
}
- (void)startPlaybackCleanup {
    if (_cleanupTimer || !_players.count) return;
    __weak MLAudio *weakSelf=self;
    _cleanupTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,_queue);
    dispatch_source_set_timer(_cleanupTimer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),NSEC_PER_SEC,100*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(_cleanupTimer, ^{
        MLAudio *audio=weakSelf; if (!audio) return;
        NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
        for (NSNumber *session in audio->_players.allKeys) {
            MLPlayback *playback=audio->_players[session];
            if (now-playback.lastPacket>2) {
                [playback.player stop]; [audio->_engine detachNode:playback.player]; [audio->_players removeObjectForKey:session];
                MLConnection *connection=audio->_connection;
                dispatch_async(dispatch_get_main_queue(), ^{ [connection.model setTalkState:MLTalkStatePassive forSession:session.unsignedIntegerValue]; });
            }
        }
        if (!audio->_players.count) { dispatch_source_cancel(audio->_cleanupTimer); audio->_cleanupTimer=nil; }
    }); dispatch_resume(_cleanupTimer);
}
- (void)stop {
    NSAssert(NSThread.isMainThread,@"Audio lifecycle runs on the main thread");
    _wantRunning=NO; _notifyRestart=NO; ++_lifecycleGeneration;
    [self stopEngine];
    [self deactivateSession];
}
- (void)stopEngine {
    _running=false; ++_generation; _engineRecoveryInFlight=NO;
    [_captureMonitorTimer invalidate]; _captureMonitorTimer=nil;
    [_engineRetryTimer invalidate]; _engineRetryTimer=nil;
    dispatch_sync(_queue, ^{
        if (self->_cleanupTimer) { dispatch_source_cancel(self->_cleanupTimer); self->_cleanupTimer=nil; }
        if (self->_tapInstalled) { [self->_engine.inputNode removeTapOnBus:0]; self->_tapInstalled=NO; }
        if (self->_captureSource) { dispatch_source_cancel(self->_captureSource); self->_captureSource=nil; }
        [self->_engine stop];
        if (self->_transmitting) [self->_connection sendOpus:[NSData data] sequence:self->_sequence terminator:YES];
        MLConnection *connection=self->_connection;
        dispatch_async(dispatch_get_main_queue(), ^{ [connection.model setTalkState:MLTalkStatePassive forSession:connection.model.connectedUser.session]; });
        for (MLPlayback *playback in self->_players.allValues) [playback.player stop];
        [self->_players removeAllObjects]; self->_encoder.reset();
        if (self->_preprocessor) speex_preprocess_state_destroy(self->_preprocessor);
        self->_preprocessor=nullptr; self->_pending.clear(); self->_transmitting=NO;
    });
    _sidetone=nil; _converter=nil; _convertedInput=nil; _engine=nil;
}
- (void)engineStartupFailed:(NSError *)error {
    NSLog(@"Audio engine startup failed: %@",error);
    [self stopEngine];
    // A route may briefly report no input while Voice Processing is settling.
    // Preserve the connection's capture intent, but bound retries for unavailable hardware.
    if (!_wantRunning || _interrupted || _engineRetryCount>=5) return;
    NSUInteger generation=_lifecycleGeneration;
    NSTimeInterval delay=MIN(.5 * ++_engineRetryCount,2.0);
    __weak MLAudio *weakSelf=self;
    _engineRetryTimer=[NSTimer timerWithTimeInterval:delay repeats:NO block:^(NSTimer *timer) {
        MLAudio *audio=weakSelf;
        if (!audio || timer!=audio->_engineRetryTimer) return;
        audio->_engineRetryTimer=nil;
        if (generation==audio->_lifecycleGeneration && audio->_wantRunning && !audio->_interrupted) [audio start];
    }];
    [NSRunLoop.mainRunLoop addTimer:_engineRetryTimer forMode:NSRunLoopCommonModes];
}
- (void)restart {
    BOOL wanted=_wantRunning || _running; [self stop];
    if (wanted) { _notifyRestart=YES; [self start]; }
}
- (void)beginAudioInterruptionWithInactiveSession:(BOOL)inactive {
    NSAssert(NSThread.isMainThread,@"Audio lifecycle runs on the main thread");
    _interrupted=YES;
    BOOL wanted=_wantRunning;
    [self setForceTransmit:NO];
    if (inactive) _sessionActive=NO;
    [self stop]; _wantRunning=wanted; _notifyRestart=wanted;
}
- (void)endAudioInterruptionMayResume:(BOOL)mayResume allowActivationRetry:(BOOL)allowRetry {
    NSAssert(NSThread.isMainThread,@"Audio lifecycle runs on the main thread");
    // Modern recommendations can also arrive after a rejected activation.
    // Legacy late end events must not interfere with an explicit recovery.
    if (!_interrupted && !(allowRetry && mayResume && _wantRunning && !self.isRunning && !_sessionTransition)) return;
    _interrupted=NO;
    BOOL wanted=_wantRunning &&
        (![self.delegate respondsToSelector:@selector(audioShouldBeRunning:)] || [self.delegate audioShouldBeRunning:self]);
    _wantRunning=wanted;
    // A connected conversation has an ongoing input/output intent, unlike a
    // paused media player. Once the interruption ends, try activating once even
    // without the media-playback hint. The system can still refuse activation.
    if (wanted && (mayResume || _connection!=nil)) [self start];
}
- (void)interrupted:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSNumber *typeValue=notification.userInfo[AVAudioSessionInterruptionTypeKey];
        if (!typeValue) return;
        NSUInteger type=typeValue.unsignedIntegerValue;
        if (type==AVAudioSessionInterruptionTypeBegan) {
            NSLog(@"Audio interrupted (legacy), connected=%d",self->_connection!=nil);
            [self beginAudioInterruptionWithInactiveSession:NO];
        } else if (type==AVAudioSessionInterruptionTypeEnded) {
            BOOL mayResume=([notification.userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue] & AVAudioSessionInterruptionOptionShouldResume)!=0;
            NSLog(@"Audio interruption ended (legacy), resume=%d",mayResume);
            [self endAudioInterruptionMayResume:mayResume allowActivationRetry:NO];
        }
    });
}
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270000
- (void)sessionBecameInactive:(NSNotification *)notification {
    if (@available(iOS 27.0, *)) {
        AVAudioSessionDeactivationContext *context=notification.userInfo[AVAudioSessionDeactivationContextKey];
        if (!context || context.source!=AVAudioSessionDeactivationSourceSystem) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"Audio session interrupted by system, reason=%lu, connected=%d",(unsigned long)context.interruptionContext.reason,self->_connection!=nil);
            [self beginAudioInterruptionWithInactiveSession:YES];
        });
    }
}
- (void)sessionMayResume:(NSNotification *)notification {
    if (@available(iOS 27.0, *)) {
        AVAudioSessionResumptionContext *context=notification.userInfo[AVAudioSessionResumptionContextKey];
        if (!context) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL mayResume=context.recommendation==AVAudioSessionResumptionRecommendationShouldResume;
            NSLog(@"Audio session resumption recommendation=%ld, connected=%d",(long)context.recommendation,self->_connection!=nil);
            [self endAudioInterruptionMayResume:mayResume allowActivationRetry:YES];
        });
    }
}
#endif
- (void)routeChanged:(NSNotification *)notification {
    NSUInteger reason=[notification.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];
    if (reason==AVAudioSessionRouteChangeReasonNewDeviceAvailable || reason==AVAudioSessionRouteChangeReasonOldDeviceUnavailable)
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->_wantRunning && !self->_sessionTransition && !self->_interrupted) {
                if (self->_engine) [self recoverStoppedEngine];
                else [self start];
            }
        });
}
- (void)recoverStoppedEngine {
    NSAssert(NSThread.isMainThread,@"Audio recovery runs on the main thread");
    if (!_wantRunning || _interrupted || _sessionTransition || _engineRecoveryInFlight || !_engine || _engine.isRunning) return;
    if (![self consumeEngineRecoveryAttempt]) return;
    _engineRecoveryInFlight=YES; _running=false;
    // Resume the existing graph without toggling AVAudioSession or recreating Voice Processing.
    AVAudioEngine *engine=_engine;
    NSUInteger lifecycle=_lifecycleGeneration;
    size_t generation=_generation;
    dispatch_async(_queue, ^{
        if (generation!=self->_generation) return;
        NSError *error=nil;
        BOOL formatChanged=self->_converter && ![[engine.inputNode outputFormatForBus:0] isEqual:self->_converter.inputFormat];
        BOOL restored=NO;
        if (!formatChanged) {
            [engine prepare];
            restored=[engine startAndReturnError:&error];
            if (restored) {
                [self->_sidetone play];
                for (MLPlayback *playback in self->_players.allValues) [playback.player play];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (lifecycle!=self->_lifecycleGeneration || generation!=self->_generation || self->_engine!=engine) return;
            self->_engineRecoveryInFlight=NO;
            if (!self->_wantRunning || self->_interrupted) return;
            if (restored) self->_running=true;
            else [self engineStartupFailed:error];
        });
    });
}
- (BOOL)consumeEngineRecoveryAttempt {
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    if (!_engineRecoveryWindow || now-_engineRecoveryWindow>30) { _engineRecoveryWindow=now; _engineRecoveryCount=0; }
    if (_engineRecoveryCount>=3) return NO;
    ++_engineRecoveryCount;
    return YES;
}
- (void)startCaptureMonitor {
    [_captureMonitorTimer invalidate];
    _lastTapSeen=_tapCount; _lastProcessedSeen=_processedCount;
    _tapChangedAt=_processedChangedAt=NSProcessInfo.processInfo.systemUptime;
    _captureWarmup=false;
    __weak MLAudio *weakSelf=self;
    _captureMonitorTimer=[NSTimer timerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer) { [weakSelf checkCaptureHealth]; }];
    _captureMonitorTimer.tolerance=.5;
    [NSRunLoop.mainRunLoop addTimer:_captureMonitorTimer forMode:NSRunLoopCommonModes];
}
- (BOOL)captureHasStalled {
    if (!_tapInstalled || !_engine) return NO;
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    uint64_t taps=_tapCount, processed=_processedCount;
    BOOL warmup=_captureWarmup.exchange(false);
    if (taps!=_lastTapSeen) { _lastTapSeen=taps; _tapChangedAt=now; }
    if (processed!=_lastProcessedSeen || warmup) {
        _lastProcessedSeen=processed; _processedChangedAt=now;
    }
    // Quiet PCM is healthy. Only missing callbacks/conversion progress count.
    return now-_tapChangedAt>4 || (_captureNeeded && now-_processedChangedAt>4);
}
- (void)checkCaptureHealth {
    NSAssert(NSThread.isMainThread,@"Capture recovery runs on the main thread");
    if (!_wantRunning || _interrupted || _sessionTransition || _engineRecoveryInFlight || !_tapInstalled || !_engine) return;
    if (!_engine.isRunning) { [self recoverStoppedEngine]; return; }
    if (![self captureHasStalled] || ![self consumeEngineRecoveryAttempt]) return;
    _engineRecoveryInFlight=YES;
    NSUInteger lifecycle=_lifecycleGeneration;
    size_t generation=_generation;
    // Drain queued DSP before rebuilding. A stalled processing queue must not
    // make the UI wait for a synchronous teardown.
    dispatch_async(_queue, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (lifecycle!=self->_lifecycleGeneration || generation!=self->_generation) return;
            self->_engineRecoveryInFlight=NO;
            if (!self->_wantRunning || self->_interrupted || self->_sessionTransition || ![self captureHasStalled]) return;
            NSLog(@"Microphone data stalled; rebuilding the audio session");
            [self stopEngine]; self->_notifyRestart=YES;
            if (self->_sessionActive) [self deactivateSession];
            else [self start];
        });
    });
}
- (void)engineConfigurationChanged:(NSNotification *)notification {
    // AVFAudio delivers this on its own queue; never tear down the engine there.
    // Engine teardown can itself post this notification. Do not retain its object into a block.
    uintptr_t changedEngine=(uintptr_t)(__bridge void *)notification.object;
    size_t generation=_generation;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation==self->_generation && changedEngine==(uintptr_t)(__bridge void *)self->_engine) [self recoverStoppedEngine];
    });
}
- (void)mediaReset:(NSNotification *)notification { dispatch_async(dispatch_get_main_queue(), ^{ [self restart]; }); }
- (void)capture:(AVAudioPCMBuffer *)input {
    if (!_captureNeeded) return;
    AVAudioPCMBuffer *converted=input;
    if (![input.format isEqual:_format]) {
        AVAudioFrameCount capacity=(AVAudioFrameCount)ceil(input.frameLength*48000/input.format.sampleRate)+8;
        if (!_convertedInput || _convertedInput.frameCapacity<capacity)
            _convertedInput=[[AVAudioPCMBuffer alloc] initWithPCMFormat:_format frameCapacity:capacity];
        converted=_convertedInput;
        converted.frameLength=0;
        __block BOOL supplied=NO;
        NSError *error=nil;
        AVAudioConverterOutputStatus result=[_converter convertToBuffer:converted error:&error withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount requested, AVAudioConverterInputStatus *status) {
            if (supplied) { *status=AVAudioConverterInputStatus_NoDataNow; return nil; }
            supplied=YES; *status=AVAudioConverterInputStatus_HaveData; return input;
        }];
        if (result==AVAudioConverterOutputStatus_Error || !converted.frameLength) return;
    }
    MLAudioSettings settings=self.settings;
    AVAudioFrameCount frameCount=converted.frameLength;
    if (!frameCount) return;
    if (_processedCount.fetch_add(1)==_processingLogBaseline)
        NSLog(@"Microphone PCM processing started: %u frames",frameCount);
    const float *inputSamples=converted.floatChannelData[0];
    size_t previousSize=_pending.size();
    _pending.resize(previousSize+frameCount);
    int16_t *outputSamples=_pending.data()+previousSize;
    for (AVAudioFrameCount i=0;i<frameCount;++i) {
        float sample=std::clamp(inputSamples[i]*settings.micBoost,-1.f,1.f);
        outputSamples[i]=(int16_t)lrintf(sample*32767);
    }
    size_t samples=(size_t)settings.audioPerPacket*480;
    size_t consumed=0;
    while (_pending.size()-consumed>=samples) {
        float peak=0, probability=0;
        for (size_t offset=0;offset<samples;offset+=480) {
            int16_t *frame=_pending.data()+consumed+offset;
            if (settings.enablePreprocessor && settings.vadKind==MLVADKindSignalToNoise && _preprocessor) {
                std::array<int16_t,480> analysis;
                std::copy_n(frame,analysis.size(),analysis.data());
                speex_preprocess_run(_preprocessor,analysis.data()); int percent=0;
                speex_preprocess_ctl(_preprocessor,SPEEX_PREPROCESS_GET_PROB,&percent); probability=std::max(probability,percent/100.f);
            }
            for (size_t i=0;i<480;++i) peak=std::max(peak,std::abs(frame[i]/32768.f));
        }
        float db=std::max(-96.f,20.f*log10f(std::max(peak,.000001f))); _peak=db; _speech=probability;
        float level=settings.vadKind==MLVADKindSignalToNoise && settings.enablePreprocessor && _preprocessor ? probability : (db+96)/96;
        BOOL transmit=settings.transmitType==MLTransmitTypeContinuous || (settings.transmitType==MLTransmitTypeToggle ? (BOOL)_forced.load() : level>=(_transmitting?settings.vadMin:settings.vadMax));
        MLConnection *connection=_connection;
        if (_localMuted) transmit=NO;
        if (transmit && connection) {
            uint32_t overhead=(uint32_t)(64*8*100/settings.audioPerPacket);
            uint32_t maximum=_bandwidthLimit;
            uint32_t bitrate=maximum ? std::min((uint32_t)settings.quality,maximum>overhead+6000?maximum-overhead:6000) : (uint32_t)settings.quality;
            if (_encoder->bitrate()!=bitrate) _encoder->setBitrate(bitrate);
            auto encoded=(*_encoder)(_encodedBuffer,mumble::Opus::IntegerViewConst(_pending.data()+consumed,samples));
            if (!encoded.empty()) [connection sendOpus:MLData(encoded) sequence:_sequence terminator:NO];
        } else if (_transmitting && connection) [connection sendOpus:[NSData data] sequence:_sequence terminator:YES];
        if (transmit!=_transmitting) {
            MLTalkState state=transmit?MLTalkStateTalking:MLTalkStatePassive;
            dispatch_async(dispatch_get_main_queue(), ^{ [connection.model setTalkState:state forSession:connection.model.connectedUser.session]; });
        }
        if (settings.enableSideTone && settings.sidetoneVolume>0 && transmit) {
            AVAudioPCMBuffer *buffer=[[AVAudioPCMBuffer alloc] initWithPCMFormat:_format frameCapacity:(AVAudioFrameCount)samples]; buffer.frameLength=(AVAudioFrameCount)samples;
            float *output=buffer.floatChannelData[0];
            for (size_t i=0;i<samples;++i) output[i]=_pending[consumed+i]/32768.f*settings.sidetoneVolume;
            [_sidetone scheduleBuffer:buffer completionHandler:nil];
        }
        _transmitting=transmit; _sequence+=samples/480; consumed+=samples;
    }
    if (consumed) _pending.erase(_pending.begin(),_pending.begin()+(long)consumed);
}
- (void)receiveOpus:(NSData *)data session:(NSUInteger)session sequence:(uint64_t)sequence terminator:(BOOL)terminator {
    // The model is only accessed on the main thread; decoding is confined to the audio queue.
    if (_localDeafened || [_connection.model userWithSession:session].isLocalMuted) return;
    dispatch_async(_queue, ^{
        if (!self->_running || self->_localDeafened) return;
        MLPlayback *playback=self->_players[@(session)];
        if (!playback && data.length) {
            playback=[MLPlayback new]; playback.player=[AVAudioPlayerNode new]; playback.lastPacket=NSProcessInfo.processInfo.systemUptime;
            [self->_engine attachNode:playback.player]; [self->_engine connect:playback.player to:self->_engine.mainMixerNode format:self->_format];
            [playback.player play]; self->_players[@(session)]=playback;
            [self startPlaybackCleanup];
        }
        if (!playback) return;
        playback.lastPacket=NSProcessInfo.processInfo.systemUptime;
        if (sequence<playback->nextSequence) return;
        if (!data.length) return;
        uint64_t gap=sequence-playback->nextSequence;
        if (playback->queuedSeconds>.4 || gap>10) { [playback.player stop]; playback->decoder->reset(); playback->queuedSeconds=0; ++playback->generation; [playback.player play]; }
        else if (gap && gap<=10) {
            for (uint64_t i=0;i<gap;++i) {
                AVAudioPCMBuffer *concealed=[playback bufferWithFormat:self->_format];
                if (!concealed) break;
                auto decoded=(*playback->decoder)(mumble::Opus::FloatView(concealed.floatChannelData[0],480),{});
                concealed.frameLength=(AVAudioFrameCount)decoded.size();
                if (concealed.frameLength) [self scheduleBuffer:concealed forPlayback:playback duration:0];
                else [playback recycleBuffer:concealed];
            }
        }
        AVAudioPCMBuffer *buffer=[playback bufferWithFormat:self->_format];
        if (!buffer) return;
        auto decoded=(*playback->decoder)(mumble::Opus::FloatView(buffer.floatChannelData[0],5760),MLBytes(data));
        buffer.frameLength=(AVAudioFrameCount)decoded.size(); if (!buffer.frameLength) { [playback recycleBuffer:buffer]; return; }
        playback->nextSequence=sequence+buffer.frameLength/480;
        double duration=buffer.frameLength/48000.0; playback->queuedSeconds+=duration;
        [self scheduleBuffer:buffer forPlayback:playback duration:duration];
    });
}
- (void)scheduleBuffer:(AVAudioPCMBuffer *)buffer forPlayback:(MLPlayback *)playback duration:(double)duration {
    NSUInteger generation=playback->generation;
    [playback.player scheduleBuffer:buffer completionCallbackType:AVAudioPlayerNodeCompletionDataPlayedBack completionHandler:^(AVAudioPlayerNodeCompletionCallbackType type) {
        dispatch_async(self->_queue, ^{
            if (generation==playback->generation) playback->queuedSeconds=std::max(0.0,playback->queuedSeconds-duration);
            [playback recycleBuffer:buffer];
        });
    }];
}
- (NSDictionary *)copyAudioOutputMixerDebugInfo {
    __block NSMutableArray *sources=[NSMutableArray array];
    dispatch_sync(_queue, ^{ for (NSNumber *session in self->_players) [sources addObject:@{@"kind":@"Opus",@"identifier":session.stringValue}]; });
    return @{@"last-update":NSDate.date,@"sources":sources,@"removed":@[]};
}
@end

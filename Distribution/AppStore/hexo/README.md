# English privacy policy for Hexo

This package publishes one English privacy policy for **Mumble (new)**.
There are no Chinese pages or separate support pages in this deployment.

| App Store Connect field | URL after deployment |
| --- | --- |
| Privacy Policy URL, all store languages | https://www.rubycore.ltd/mumble/privacy/ |

The page includes the public contact email, `apple@piggy.live`, and identifies
the app as independently maintained by **blakebill**. It links directly to email
support, without links to unpublished translations or support pages.

## Website source

The website development folder is `/Volumes/Files/Hexo_Dev/`. Copy only
`source/mumble/privacy/index.md` from this package to the same relative path
inside that folder. Do not copy the templates, configuration or review notes
into the public website.

The page uses Hexo's standard page layout, English language, disabled comments
and the fixed permalink `mumble/privacy/`. It is not a blog post.

Generate and preview using the website's existing Hexo installation. Check the
page on a phone and desktop, including headings, contact links and the complete
policy text. Confirm the final HTTPS address is publicly accessible before
entering it in App Store Connect.

The existing `_config.yml` deployment target is
`git@github.com:blakebill/blakebill.github.io.git`, branch `master`, while its
site URL is `https://rubycore.org`. Confirm the current production publishing
route before running `hexo deploy`: it publishes the entire generated site,
including other uncommitted website changes. This package does not change
those settings or assume that adding the source file makes the URL live.

Use the `www.rubycore.ltd` hostname for the prepared policy URL. The bare
`rubycore.ltd` hostname failed TLS hostname verification during preparation;
do not bypass certificate verification.

## Update the page

Edit `templates/privacy.en.md` for policy text, or `site.json` for the app name,
publisher, email and effective date. From the app repository, run:

```sh
python3 Distribution/AppStore/hexo/prepare-pages.py
python3 Distribution/AppStore/hexo/prepare-pages.py --check
```

The generator writes only `source/mumble/privacy/index.md`. Copy the updated
page into the website and publish it through the confirmed production workflow.
Publishing a privacy policy does not itself complete content-safety,
account-deletion, encryption or App Store privacy-label requirements.

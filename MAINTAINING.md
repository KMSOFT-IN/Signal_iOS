Apart from the general `BUILDING.md` there are certain things that have
to be done by Signal-iOS maintainers.

For transparency and bus factor, they are outlined here.

## Dependencies

Keeping CocoaPods based dependencies is easy enough.

- To just update one dependency: `bundle exec pod update DependencyKit`
- To update all dependencies to the latest according to the Podfile range: `bundle exec pod update`

Some Signal Pods have prebuilt artifacts that need a checksum to be downloaded as part of the build.
These are provided by the CallingCore team.

## Translations

Read more about translations in [TRANSLATIONS.md](Signal/translations/TRANSLATIONS.md)

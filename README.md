# playwright-perl [![Build Status](https://travis-ci.org/teodesian/playwright-perl.svg?branch=main)](https://travis-ci.org/teodesian/playwright-perl) [![Coverage Status](https://coveralls.io/repos/github/teodesian/playwright-perl/badge.svg?branch=main)](https://coveralls.io/github/teodesian/playwright-perl?branch=main)

Perl bindings for [playwright][pw], the amazing cross browser testing framework from Microsoft

## Has this ever happened to you?

You're writing some acceptance test with [Selenium::Remote:Driver][srd], but you figure out selenium is a dead protocol?
Finally, a solution!

## Here's how it works

A little node webserver written in [express][xp] is spun up which exposes the entire playwright API.
We ensure the node deps are installed in a BEGIN block, and then spin up the proxy server.
You then use playwright more or less as normal; see the POD in Playwright.pm for more details.

See example.pl for usage examples.

[pw]:https://github.com/microsoft/playwright
[srd]:https://metacpan.org/pod/Selenium::Remote::Driver
[xp]:http://expressjs.com/

# Supported Perls

Everything newer than 5.28 is supported.

Things should work on 5.20 or newer, but...
Tests might fail due to Temp file weirdness with Test::MockFile.

## How2develop

Everything should more or less set itself up automatically, or explode and tell you what to do.
I assume you know how to get cpanm.

You might want to use distro packages for some of these:

```
sudo cpanm Dist::Zilla
dzil authordeps --missing | sudo cpanm
dzil listdeps --missing | sudo cpanm
```

Actually running stuff:

`perl -Ilib example.pl`

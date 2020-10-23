# playwright-perl
Perl bindings for [playwright][pw], the amazing cross browser testing framework from Microsoft

## Has this ever happened to you?

You're writing some acceptance test with [Selenium::Remote:Driver][srd], but you figure out selenium is a dead protocol?
Finally, a solution!

## Here's how it works

A little node webserver written in [express][xp] is spun up which exposes the entire playwright API.
You build a bunch of little actions to do much like action chains in Selenium, and then make 'em go whir.

See example.pl for usage examples.

[pw]:https://github.com/microsoft/playwright
[srd]:https://metacpan.org/pod/Selenium::Remote::Driver
[xp]:http://expressjs.com/
[xs]:https://metacpan.org/pod/Promise::XS

## How2develop

npm i playwright express uuid yargs

perl -Ilib example.pl

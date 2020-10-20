# playwright-perl
Perl bindings for [playwright][pw]

## Has this ever happened to you?

You're writing some acceptance test with [Selenium::Remote:Driver][srd], but you figure out selenium is a dead protocol?
Finally, a solution!

## Here's how it works

A little node webserver written in [express][xp] is spun up which exposes the entire playwright API.
You build a bunch of little actions to do much like action chains in Selenium, and then make 'em go whir.

The best way to do this is probably using [Promise::XS][xs].

## How2develop

npm i playwright express
perl -Ilib example.pl

# SystemD service files

These are tested on ubuntu and centos, but should generally work on similar distros.
Contributions welcome for other distros and init systems.

## Setting up

This assumes you have already `nvm install` and `nvm use node` on your desired node version.
The node binary used at the time you run the makefile will be hardcoded into `playwright_server`.

Run `PORT=6969 make install-service` and things should "just work (TM)".
Replace port as appropriate.

Manage service with `systemctl --user $VERB playwright`
where $VERB is reload, restart, stop et cetera.

## TODO

Make playwright\_server reload on HUP

Make playwright\_server have superdaemon functionality (see issue #52)

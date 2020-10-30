#!/usr/bin/node

"use strict";

const yargs = require('yargs');
const { v4 : uuidv4 } = require('uuid');
const express = require('express');
const { chromium, firefox, webkit, devices } = require('playwright');

const fs = require('fs');

// Defines our interface
let rawdata = fs.readFileSync('api.json');
let spec = JSON.parse(rawdata);

//TODO support device commands
const argv = yargs
    .option('debug', {
        alias: 'd',
        description: 'Print additional debugging messages',
        type: 'boolean',
    })
    .option('port', {
        alias: 'p',
        description: 'Run on specified port',
        type: 'number',
    })
    .help()
    .alias('help', 'h')
    .argv;

const app = express();
const port = argv.port || 6969;

var objects = {};
var browsers = { 'firefox' : firefox, 'chrome' : chromium, 'webkit' : webkit };

//Stash for users to put data in
var userdata = {};

app.use(express.json())

app.post('/session', async (req, res) => {
	var payload = req.body;
    var type    = payload.type;
    var args    = payload.args || [];


    var result;
    if ( type && browsers[type] ) {
        try {
            var browser = await browsers[type].launch(...args);
            objects[browser._guid] = browser;
            result = { error : false, message : browser };
        } catch (e) {
            result = { error : true, message : e.message};
        }
    } else {
        result = { error : true, message : "Please select a supported browser" };
    }
    res.json(result);
});

app.post('/command', async (req, res) => {

    var payload = req.body;
    var type    = payload.type;
    var object  = payload.object;
    var command = payload.command;
    var args    = payload.args || [];
    var result = {};

    if (argv.debug) {
        console.log(type,object,command,args);
    }

    // XXX this would be cleaner if the mouse() and keyboard() methods just returned a Mouse and Keyboard object
    var subject = objects[object];
    if (subject) {
        if (type == 'Mouse') {
            subject = objects[object].mouse;
        } else if (type == 'Keyboard' ) {
            subject = objects[object].keyboard;
        }
    }

    if (subject && spec[type] && spec[type].members[command]) {
        try {

            //XXX We have to do a bit of 'special' handling for scripts
            // This has implications for the type of scripts you can use
            if (command == 'evaluate' || command == 'evaluateHandle') {
                var toEval = args.shift();
                const fun = new Function (toEval);
                args = [
                    fun,
                    ...args
                ];
            }

            const res = await subject[command](...args);
            result = { error : false, message : res };

            if (Array.isArray(res)) {
                for (var r of res) {
                    objects[r._guid] = r;
                }
            }

            // XXX videos are special, we have to magic up a guid etc for them
            if (command == 'video' && res) {
                res._guid = 'Video@' + uuidv4();
                res._type = 'Video';
            }
            // XXX So are FileChooser object unfortunately
            if (args[0] == 'filechooser' && res) {
                res._guid = 'FileChooser@' + uuidv4();
                res._type = 'FileChooser';
            }

            if (res && res._guid) {
                objects[res._guid] = res;
            }
        } catch (e) {
            result = { error : true, message : e.message };
        }
    // Allow creation of event listeners if we can actually wait for them
    } else if (command == 'on' && subject && spec[type].members.waitForEvent ) {
        try {
            var evt = args.shift();
            const cb  = new Function (args.shift());
            subject.on(evt,cb);
            result = { error : false, message : "Listener set up" };
        } catch (e) {
            result = { error : true, message : e.message };
        }
    } else {
        result = { error : true, message : "No such object, or " + command + " is not a globally recognized command for puppeteer" };
    }

    res.json(result);
});

app.get('/shutdown', async (req, res) => {
    res.json( { error: false, message : "Sent kill signal to browser" });
    process.exit(0);
});

//Modulino
if (require.main === module) {
    app.listen( port, () => {
        if (argv.debug) {
            console.log(`Listening on port ${port}`);
        }
    });
}

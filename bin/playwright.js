#!/usr/bin/node

"use strict";

const yargs = require('yargs');
const uuid = require('uuid');
const express = require('express');
const { chromium, firefox, webkit, devices } = require('playwright');

const fs = require('fs');

// Defines our interface
let rawdata = fs.readFileSync('api.json');
let spec = JSON.parse(rawdata);

//TODO support device commands
const argv = yargs
    .command('firefox', 'Starts a playwright instance of firefox', {
        firefox: {
            description: 'Start a firefox instance',
            alias: 'f',
            type: 'boolean',
        }
    })
    .command('chrome', 'Starts a playwright instance of chrome', {
        chrome: {
            description: 'Start a chrome instance',
            alias: 'c',
            type: 'boolean',
        }
    })
    .command('webkit', 'Starts a playwright instance of webkit', {
        webkit: {
            description: 'Start a webkit instance',
            alias: 'w',
            type: 'boolean',
        }
    })
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
    .option('visible', {
        alias: 'v',
        description: 'Run with headless mode off',
        type: 'boolean',
    })
    .help()
    .alias('help', 'h')
    .argv;

const app = express();
const port = argv.port || 6969;

var objects = {};

app.use(express.json())

app.get('/session', async (req, res) => {
    if (argv._.includes('firefox')) {
        objects.browser = await firefox.launch( { "headless" : !argv.visible } );
    }
    if (argv._.includes('chrome')) {
        objects.browser = await chromium.launch( { "headless" : !argv.visible } );
    }
    if (argv._.includes('webkit')) {
        objects.browser = await webkit.launch( { "headless" : !argv.visible } );
    }

    if (!objects.browser) {
        console.log('no browser selected, begone');
        process.exit(1);
    }

    if (argv.debug) {
        console.log('Browser Ready for use');
    }
    res.json({ error: false, message: 'Browser started successfully.' });
});

app.post('/command', async (req, res) => {

	var payload = req.body;
    var type    = payload.type;
    var object  = payload.object;
    var command = payload.command;
    var args    = payload.args || [];

    var result = {};

    if (objects[object] && spec[type] && spec[type].members[command]) {
        try {
            const res = await objects[object][command](...args);
            result = { error : false, message : res };

            if (res._guid) {
                objects[res._guid] = res;
            }
        } catch (e) {
            result = { error : true, message : e.message };
        }
    } else {
        result = { error : true, message : "No such object, or " + command + " is not a globally recognized command for puppeteer" };
    }

    res.json(result);
});

app.get('/shutdown', async (req, res) => {
    if (objects.browser) {
        await objects.browser.close();
    }
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

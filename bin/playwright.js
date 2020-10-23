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

var browser;
var pages = {};
var responses = {};

//XXX this is probably a race but I don't care yet
app.use(express.json())

app.get('/session', async (req, res) => {
    if (argv._.includes('firefox')) {
        browser = await firefox.launch( { "headless" : !argv.visible } );
    }
    if (argv._.includes('chrome')) {
        browser = await chromium.launch( { "headless" : !argv.visible } );
    }
    if (argv._.includes('webkit')) {
        browser = await webkit.launch( { "headless" : !argv.visible } );
    }

    if (!browser) {
        console.log('no browser selected, begone');
        process.exit(1);
    }
    pages.default = await browser.newPage();

    if (argv.debug) {
        console.log('Browser Ready for use');
    }
    res.json({ error: false, message: 'Browser started successfully.' });
});

app.get('/command', async (req, res) => {

	var payload = req.query;
    var page    = payload.page;
    var result  = payload.result;
    var command = payload.command;
    var args    = payload.args || [];

    var result = {};
    if (typeof args !== 'Array') {
        args = [args];
    }

    if (pages[page] && spec.Page.members[command]) {
        // Operate on the provided page
        const res = await pages[page][command](...args);
        result = { error : false, message : res };
    } else if ( responses[result] && spec.Result.members[command]) {
        const res = await responses[result][command]
        result = { error : false, message : res };
    } else if ( spec.Browser.members[command] || spec.BrowserContext.members[command] ) {
        const res = await browser[command](...args);

        //File things away for our client modules to interact with
        if (command == 'newPage') {
            pages[res._guid] = res;
        }
        if (res._type === 'Response') {
            responses[res._guid] = res;
        }

        result = { error : false, message : res };
    } else {
        result = { error : true, message : "No such page, or " + command + " is not a globally recognized command for puppeteer" };
    }

    res.json(result);
});

app.get('/shutdown', async (req, res) => {
    if (browser) {
        await browser.close();
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

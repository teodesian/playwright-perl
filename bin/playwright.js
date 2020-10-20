#!/usr/bin/node

"use strict";

const yargs = require('yargs');
const uuid = require('uuid');
const express = require('express');
const { chromium, firefox, webkit, devices } = require('playwright');

const fs = require('fs');

//TODO use this to define the interface for /command
let rawdata = fs.readFileSync('api.json');
let spec = JSON.parse(rawdata);

//console.log(spec);

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

//XXX this is probably a race but I don't care yet
(async () => {
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
        console.log(argv);
        console.log('no browser selected, begone');
        process.exit(1);
    }
    pages.default = await browser.newPage();
    pages.default.goto('http://google.com');
    console.log('Browser Ready for use');

})();

var results = {};

app.use(express.json())
app.get('/command', async (req, res) => {

	var payload = req.query;
    var page    = payload.page || 'default';
    var command = payload.command;
    var args    = payload.args;

    console.log(...args);

    var result = {};

    if (pages[page]) {
        const res = await pages[page][command](...args);
        result = { error : false, message : res };
    } else {
        result = { error : true, message : "No such page, or " + command + " is not a globally recognized command for puppeteer" };
    }

    res.json(result);
});

app.get('/shutdown', async (req, res) => {
    console.log('shutting down...');
    await browser.close();
    console.log('done');
    res.send("Sent kill signal to browser");
    process.exit(0);
});

//Modulino
if (require.main === module) {
    app.listen( port, () => {
	    console.log(`Listening on port ${port}`);
    });
}

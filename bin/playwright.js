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
    var browser;
    if (argv._.includes('firefox')) {
        browser = await firefox.launch( { "headless" : !argv.visible } );
    }
    if (argv._.includes('chrome')) {
        browser = await chrome.launch( { "headless" : !argv.visible } );
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
//app.use(express.urlencoded({ extended: true }))
app.get('/command', (req, res) => {

	var payload = req.body;
    var page = payload.page;
    var command = payload.command;
    var result = {};
	if (pages[page]) {
        if (pages[page][command]) {
            //TODO execute, return result
            result = { error : false, value : command, type : "page" };
        } else {
            result = { error : true, message : "Invalid command '" + command + "' to issue to page '" + page + "'." };
        }
    } else if (browser[command]) {
        //TODO execute, return result
        result = { error : false, value : command, type : "global" };
    } else {
        result = { error : true, message : "No such page, or " + command + " is not a globally recognized command for puppeteer" };
    }
    res.json(result);
});

// XXX this hangs for some reason.
// Maybe I shouldn't care and just send SIGTERM tho
// ^C seems to not leave zommies
app.get('/shutdown', (req, res) => {
    (async () => {i
        console.log('shutting down...');
        await browser.close();
        console.log('done');
        process.exit(0);

        res.send("Sent kill signal to browser");
    });
});

//Modulino
if (require.main === module) {
    app.listen( port, () => {
	    console.log(`Listening on port ${port}`);
    });
}

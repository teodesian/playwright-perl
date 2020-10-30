#!/usr/bin/node

"use strict";

const fs = require('fs');

// Defines our interface
let rawdata = fs.readFileSync('api.json');
let spec = JSON.parse(rawdata);

for (var classname of Object.keys(spec)) {
    for (var method of Object.keys(spec[classname].members)) {
        var order = 0;
        for (var arg of Object.keys(spec[classname].members[method].args) ) {
            spec[classname].members[method].args[arg].order = order++;
        }
    }
}

fs.writeFileSync('api.json',JSON.stringify(spec));

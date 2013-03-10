jspiet
======

A Piet to Javascript JIT compiler. Because why not?

While something of a work in progress, it can currently quite happily run the demo programs for npiet.

To run via node, first install dependencies, then:
    $ coffee cli.coffee program.ppm

Alternatively jspiet can be used in the browser. Install jquery and underscore.js to lib, then:
    $ coffee -cb *.coffee

Note that the generated .js files will have to be removed if you want to use node again. I should probably package this properly to avoid this.

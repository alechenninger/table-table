// Forward optional fixture filters to a dart2js benchmark's main(arguments).
const path = require('node:path');

globalThis.dartMainRunner = (main) => main(process.argv.slice(3));
require(path.resolve(process.argv[2]));

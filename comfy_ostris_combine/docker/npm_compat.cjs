const Module = require('node:module');
const path = require('node:path');
const originalLoad = Module._load;
const workspace = path.resolve(process.env.A1_WORKSPACE || '/workspace');
const wrapped = Symbol.for('a1.tar.extract');

Module._load = function (request, parent, isMain) {
  const value = originalLoad.call(this, request, parent, isMain);
  if (request === 'tar-fs' && typeof value.extract === 'function' && !value[wrapped]) {
    const extract = value.extract;
    value.extract = function (cwd, options) {
      const target = path.resolve(cwd || process.cwd());
      const relative = path.relative(workspace, target);
      if (relative === '' || (relative !== '..' && !relative.startsWith('..' + path.sep) && !path.isAbsolute(relative))) {
        options = { ...options, chown: false };
      }
      return extract.call(this, cwd, options);
    };
    value[wrapped] = true;
  }
  return value;
};

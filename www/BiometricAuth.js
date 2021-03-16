var exec = require('cordova/exec');

exports.analyze = function (docPath, lang, success, error) {
    exec(success, error, 'BiometricAuth', 'analyze', [docPath, lang]);
};

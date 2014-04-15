// Generated by CoffeeScript 1.6.3
(function() {
  var CDNJS_ROOT, async, createFileMap, fs, glob, npm, path, request, tarball, updatePackageDB, verifyFilesExist, writeNpmMap, _;

  _ = require('underscore');

  async = require('async');

  fs = require('fs-extra');

  glob = require('glob');

  path = require('path');

  npm = require('npm');

  tarball = require('tarball-extract');

  request = require('request');

  CDNJS_ROOT = '/Users/misha/Projects/github/cdnjs/ajax/libs/';

  if (fs.existsSync(path.join(__dirname, 'temp'))) {
    fs.removeSync(path.join(__dirname, 'temp'));
  }

  writeNpmMap = function(obj) {
    var json;
    json = fs.readJSONFileSync(obj["package"]);
    json.npmName = obj.name;
    json.npmFileMap = [
      {
        "basePath": "/",
        "files": obj.files
      }
    ];
    fs.writeJSONFileSync(obj["package"], json);
    return console.log("Added npmFileMap to: " + obj.name);
  };

  verifyFilesExist = function(obj) {
    var notFound;
    notFound = [];
    _.each(obj.files, function(f) {
      if (!fs.existsSync(path.join(obj.unpacked, f))) {
        return notFound.push(f);
      }
    });
    if (notFound.length === 0) {
      console.log("All files in [" + obj.name + "] exist in npm!");
      return writeNpmMap(obj);
    } else {
      return console.log(("Couldnt find all files in [" + obj.name + "] - missing: ") + notFound.join(', '));
    }
  };

  createFileMap = function(obj) {
    var dest, s, tempFile, tmp;
    tmp = path.join(__dirname, 'temp', obj.name);
    tempFile = path.join(tmp, obj.name + '.tgz');
    dest = path.join(tmp, obj.ver);
    fs.mkdirsSync(dest);
    s = request.get({
      url: obj.tarball
    });
    s.pipe(fs.createWriteStream(tempFile));
    s.on('end', function() {
      return tarball.extractTarball(tempFile, dest, function(err) {
        if (!err) {
          obj.unpacked = path.join(dest, 'package');
          return verifyFilesExist(obj);
        }
      });
    });
    return s.on('error', function(err) {
      return console.log('some badness: ', err);
    });
  };

  updatePackageDB = function(cb) {
    return npm.load(npm.config, function(err) {
      var packages;
      packages = glob.sync(CDNJS_ROOT + "*/package.json");
      return async.eachSeries(packages, function(pkg, cb) {
        var name, p, ver;
        p = fs.readJsonFileSync(pkg);
        name = p.name;
        ver = p.version;
        if (!p.npmFileMap) {
          return npm.commands.view([name + "@" + ver], function(err, result) {
            var files, found, libpath, match;
            if (result) {
              match = result[ver];
              if (match) {
                libpath = path.join(path.dirname(pkg), ver);
                files = _.map(glob.sync(libpath + "**/*"), function(f) {
                  return path.relative(libpath, f);
                });
                found = {
                  tarball: match.dist.tarball,
                  files: files,
                  "package": pkg,
                  name: name,
                  ver: ver
                };
                createFileMap(found);
              }
            }
            return cb();
          });
        } else {
          return cb();
        }
      }, function(err) {
        console.log('scan done');
        return cb();
      });
    });
  };

  updatePackageDB(function() {});

}).call(this);

/*
//@ sourceMappingURL=app.map
*/

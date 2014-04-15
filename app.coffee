_ = require('underscore')
async = require('async')
fs = require('fs-extra')
glob = require('glob')
path = require('path')
npm = require('npm')
tarball = require('tarball-extract')
request = require('request')

#TODO:
# - look at latest version npms also to find our files
# - fuzzy npm name matching
# - use github api to create an issue in libs that cant be found on npm

CDNJS_ROOT = '/Users/misha/Projects/github/cdnjs/ajax/libs/' #change me!
START_FROM_SCRATCH = true #download all npms on every run (and clear temp dir)
BLACKLIST = ['noisy'] #these cause npm to throw an exception



updated = []
errors = []
npmNotFound = []
filesDontMatch = []
upToDate = []

if START_FROM_SCRATCH and fs.existsSync(path.join(__dirname, 'temp'))
  fs.removeSync(path.join(__dirname, 'temp'))


RegExp.escape = (s) ->
  return s.replace(/[-\/\\^$*+?.()|[\]{}]/g, '\\$&');


writeNpmMap = (obj, cb) ->
  json = fs.readJSONFileSync(obj.package)
  json.npmName = obj.name

  json.npmFileMap = [{
    "basePath": "/",
    "files": obj.files
  }]
  fs.writeJSONFileSync(obj.package, json)
  console.log("Added npmFileMap to: #{obj.name}")
  updated.push(obj)
  cb()

verifyFilesExist = (obj, cb) ->
  notFound = []
  foundFiles = []
  unpackedFiles = glob.sync(obj.unpacked+"/**/*.*")
  _.each(obj.files, (f) ->
    found = _.find(unpackedFiles, (uf) ->
      fname = path.basename(uf)
      return fname == path.basename(f)
    )
    if found
      foundFiles.push(path.relative(obj.unpacked, found))
    else
      notFound.push(f)
  )
  if notFound.length == 0
    console.log("All files in [#{obj.name}] exist in npm!")
    obj.files = foundFiles #fix paths to point to files in npm (may be different than in dir structure)
    writeNpmMap(obj, cb)
  else
    console.log("Couldnt find all files in [#{obj.name}] - missing: "+notFound.join(', '))
    filesDontMatch.push(obj)
    cb()

createFileMap = (obj, cb) ->
  tmp = path.join(__dirname, 'temp', obj.name)
  tempFile = path.join(tmp, obj.name+'.tgz')
  dest = path.join(tmp, obj.ver)

  done = ->
    obj.unpacked = path.join(dest, 'package')
    verifyFilesExist(obj, cb)

  if fs.existsSync(dest)
    done()
  else
    fs.mkdirsSync(dest)
    s = request.get(url: obj.tarball)
    s.pipe(fs.createWriteStream(tempFile))
    s.on('end', ->
      tarball.extractTarball(tempFile, dest, (err) ->
        if err
          errors.push(obj)
          cb()
        else
          done()
      )
    )



updatePackages = (cb) ->
  npm.load(npm.config, (err) ->

    packages = glob.sync(CDNJS_ROOT+"*/package.json")

    async.eachSeries(packages, (pkg, cb) ->
      p = fs.readJsonFileSync(pkg)
      name = p.name
      ver = p.version

      if not p.npmFileMap and name not in BLACKLIST
        console.log('npm view', name+"@"+ver)
        npm.commands.view([name+"@"+ver], (err, result) ->
          if result
            match = result[ver]
            if match
              libpath = path.join(path.dirname(pkg), ver)
              files = _.map(glob.sync(libpath+"/**/*.*"), (f) -> path.relative(libpath, f))
              found =
                tarball: match.dist.tarball
                files: files
                package: pkg
                name: name
                ver: ver

              return createFileMap(found, cb)

          console.log('npm not found: ', name)
          npmNotFound.push(name)
          cb()
        )
      else
        upToDate.push(name)
        cb()
    , (err) ->
      cb()
    )
  )

updatePackages( ->
  console.log('package scan done:')
  console.log('------------------')
  console.log('updated:', updated.length)
  console.log(_.map(updated, (o) -> o.name))
  console.log('npmNotFound:', npmNotFound.length)
  console.log(npmNotFound)
  console.log('filesDontMatch:', filesDontMatch.length)
  console.log(_.map(filesDontMatch, (o) -> o.name))
  console.log('upToDate:', upToDate.length)
  console.log(upToDate)
  console.log('errors:', errors.length)
  console.log(errors)


)


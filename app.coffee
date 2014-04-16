_ = require('underscore')
async = require('async')
fs = require('fs-extra')
glob = require('glob')
path = require('path')
npm = require('npm')
tarball = require('tarball-extract')
request = require('request')
crypto = require('crypto')
winston = require('winston')

logFile = path.join(__dirname, 'convert.log')

if fs.existsSync(logFile)
  fs.removeSync(logFile)

logger = new (winston.Logger)({
  transports: [
    new (winston.transports.Console)(),
    new (winston.transports.File)({ filename: logFile, json: false })
  ]
})



config = require("./config.json")
#TODO:
# - look at latest version npms also to find our files
# - fuzzy npm name matching
# - use github api to create an issue in libs that cant be found on npm

CDNJS_ROOT = config.root
START_FROM_SCRATCH = config.cleanStart #download all npms on every run (and clear temp dir)
BLACKLIST = config.blacklist #these cause npm to throw an exception
ALLOW_MISSING_MINJS = config.allowMissingMinJS
CHECK_MD5 = config.checkMD5 #all files we find in the npm tarballs must be identical to the ones in cdnjs by md5

updated = []
errors = []
npmNotFound = []
filesDontMatch = []
md5DontMatch = []
upToDate = []

if START_FROM_SCRATCH and fs.existsSync(path.join(__dirname, 'temp'))
  fs.removeSync(path.join(__dirname, 'temp'))


RegExp.escape = (s) ->
  return s.replace(/[-\/\\^$*+?.()|[\]{}]/g, '\\$&');


compareFiles = (f1, f2, cb) ->
  if not f1 or not f2
    return cb(true)

  hash = (file) ->
    return (cb) ->
      if not CHECK_MD5
        return cb(null, "not checking md5")

      md5sum = crypto.createHash('md5');
      s = fs.ReadStream(file)
      s.on('data', (d) ->
        md5sum.update(d)
      )
      s.on('end', (d) ->
        cb(null, md5sum.digest('hex'))
      )
  async.parallel([
    hash(f1)
    hash(f2)
  ], (err, hashes) ->
    cb(err, hashes[0] == hashes[1], hashes[0], hashes[1])
  )

writeNpmMap = (obj, cb) ->
  if obj.files.length == 0
    logger.warn("wanted to write an npm map for #{obj.name} with 0 files. This is a bug!")
    return cb()

  json = fs.readJSONFileSync(obj.package)
  json.npmName = obj.name

  json.npmFileMap = [{
    "basePath": "/",
    "files": obj.files
  }]
  fs.writeJSONFileSync(obj.package, json)
  logger.info("Added npmFileMap to: #{obj.name}")
  updated.push(obj)
  cb()

verifyFilesExist = (obj, cb) ->
  notFound = []
  badMD5 = []
  foundFiles = []

  logger.info("Verifing that all files exist in [#{obj.name}] ...")

  unpackedFiles = glob.sync(obj.unpacked+"/**/*.*")

  findFileInNpm = (f) ->
    found = _.find(unpackedFiles, (uf) -> #first try to find in the same location
      upath = path.relative(obj.unpacked, uf)
      return upath == f
    )
    return found or _.find(unpackedFiles, (uf) -> #try to find in other locations, find by filename
      ubase = path.basename(uf)
      fbase = path.basename(f)
      return ubase == fbase
    )

  noCompare = (f1, f2, cb) ->
    cb(not f1 or not f2, true) #the files do need to exist

  async.eachLimit(obj.files, 10, (f, cb) ->
    found = findFileInNpm(f)
    compareFn = compareFiles
    if not found and ALLOW_MISSING_MINJS
      origFile = f.replace(".min.js", ".js")
      found = findFileInNpm(origFile)
      compareFn = noCompare #original file will not match minified, so skip compare step

    cdnFile = path.join(obj.path, f)
    compareFn(found, cdnFile, (err, match, h1, h2) ->
      if err
        #this means there was no file with same name found in npm
        notFound.push(f)
      else if match
        foundFiles.push(path.relative(obj.unpacked, found))
      else
        logger.info("[#{obj.name}] md5 does not match: ", found, cdnFile, h1, h2)
        badMD5.push(f)
      cb()
    )
  , (err) ->
    if notFound.length == 0 and badMD5.length == 0
      logger.info("All files in [#{obj.name}] exist in npm!")
      obj.files = _.uniq(foundFiles) #fix paths to point to files in npm (may be different than in dir structure)
      writeNpmMap(obj, cb)
    else
      logger.info("Couldnt find all files in [#{obj.name}]:")
      if notFound.length
        logger.info("   Missing: "+notFound.join(', '))
        filesDontMatch.push(obj)
      if badMD5.length
        logger.info("   Bad MD5: "+badMD5.join(', '))
        md5DontMatch.push(obj)

      cb()
  )


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
                path: libpath
                ver: ver

              return createFileMap(found, cb)

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
  logger.info('package scan done:')
  logger.info('------------------')
  logger.info('updated:', updated.length)
  logger.info("     "+_.map(updated, (o) -> o.name).join(", ")) if updated.length
  logger.info('npm not found:', npmNotFound.length)
  logger.info("     "+npmNotFound.join(", ")) if npmNotFound.length
  logger.info('not all files in npm:', filesDontMatch.length)
  logger.info("     "+_.map(filesDontMatch, (o) -> o.name).join(", ")) if filesDontMatch.length
  logger.info('MD5 mismatch:', md5DontMatch.length)
  logger.info("     "+_.map(md5DontMatch, (o) -> o.name).join(", ")) if md5DontMatch.length
  logger.info('already converted:', upToDate.length)
  logger.info("     "+upToDate.join(", ")) if upToDate.length
  logger.info('errors:', errors.length)
  logger.info("     "+errors.join(", ")) if errors.length
  console.log("See convert.log for full log")

)


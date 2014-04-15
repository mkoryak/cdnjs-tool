_ = require('underscore')
async = require('async')
fs = require('fs-extra')
glob = require('glob')
path = require('path')
npm = require('npm')
tarball = require('tarball-extract')
request = require('request')

CDNJS_ROOT = '/Users/misha/Projects/github/cdnjs/ajax/libs/' #change me!


if fs.existsSync(path.join(__dirname, 'temp'))
  fs.removeSync(path.join(__dirname, 'temp'))


writeNpmMap = (obj) ->
  json = fs.readJSONFileSync(obj.package)
  json.npmName = obj.name

  json.npmFileMap = [{
    "basePath": "/",
    "files": obj.files
  }]
  fs.writeJSONFileSync(obj.package, json)
  console.log("Added npmFileMap to: #{obj.name}")

verifyFilesExist = (obj) ->
  notFound = []
  _.each(obj.files, (f) ->
    if not fs.existsSync(path.join(obj.unpacked, f))
      notFound.push(f)
  )
  if notFound.length == 0
    console.log("All files in [#{obj.name}] exist in npm!")
    writeNpmMap(obj)
  else
    console.log("Couldnt find all files in [#{obj.name}] - missing: "+notFound.join(', '))

createFileMap = (obj) ->
  tmp = path.join(__dirname, 'temp', obj.name)
  tempFile = path.join(tmp, obj.name+'.tgz')
  dest = path.join(tmp, obj.ver)
  fs.mkdirsSync(dest)
  s = request.get(url: obj.tarball)
  s.pipe(fs.createWriteStream(tempFile))
  s.on('end', ->
    tarball.extractTarball(tempFile, dest, (err) ->
      if not err
        obj.unpacked = path.join(dest, 'package')
        verifyFilesExist(obj)
    )
  )
  s.on('error', (err) ->
    console.log('some badness: ', err)
  )




updatePackageDB = (cb) ->
  npm.load(npm.config, (err) ->

    packages = glob.sync(CDNJS_ROOT+"*/package.json")


    async.eachSeries(packages, (pkg, cb) ->
      p = fs.readJsonFileSync(pkg)
      name = p.name
      ver = p.version

      if not p.npmFileMap
        npm.commands.view([name+"@"+ver], (err, result) ->
          if result
            match = result[ver]
            if match
              libpath = path.join(path.dirname(pkg), ver)
              files = _.map(glob.sync(libpath+"**/*"), (f) -> path.relative(libpath, f))
              found =
                tarball: match.dist.tarball
                files: files
                package: pkg
                name: name
                ver: ver

              createFileMap(found)

          cb()

        )
      else
        cb()
    , (err) ->
      console.log('scan done')
      cb()
    )
  )

updatePackageDB( ->

)


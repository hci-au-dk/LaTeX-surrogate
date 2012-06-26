fs = require 'fs'
rimraf = require 'rimraf'

# Defines
ROOT = 'filecache'

class FileCache
    constructor: () ->
        # Check that the root exists - and create it if it does not.
        fs.stat ROOT, (err, stats) ->
            if err
                if err.errno == 34
                    # The directory does not exist.
                    fs.mkdir ROOT, 0o0750, (err) ->
                        if err
                            console.log "Error creating root directory for the file cache."
                            process.exit 1
                else
                    console.log 'An error occurred checking the file cache root directory.'
                    console.log err
                    process.exit 1

    cachePath: (name) ->
        return ROOT + '/' + name

    cacheExists: (name) ->
        try
            stats = fs.statSync ROOT + '/' + name
            return stats.isDirectory()
        catch error
            return false

    createCache: (name) ->
        # Creates a new, named cache.
        # Start by checking whether the a cache of that name already exists.
        try
            stats = fs.statSync ROOT + '/' + name
            return false
        catch error
            if error.errno != 34
                return false

        # Create the directory
        try
            fs.mkdirSync ROOT + '/' + name, 0o0750
        catch error
            console.log 'Error creating cache directory ' + name
            return false

        return true

    removeCache: (name) ->
        # Remove a named cache from the file cache.
        try
            rimraf.sync ROOT + '/' + name
        catch error
            console.log 'Error deleting cache dir.'
            console.log error #DEBUG
            return false
        return true

    writeFile: (cacheName, fileName, fileData) ->
        # Write a single file to the cache. The cache is oblivious to the fact that it may be overwriting an old file.
        if not @cacheExists cacheName
            console.log "Attempt to write to nonexistent cache."
            return false

        try
            fs.writeFile ROOT + '/' + cacheName + '/' + fileName, fileData
            return true
        catch error
            console.log "Error writing file " + fileName + " into cache " + cacheName
            console.log error
            return false

    mkdir: (cacheName, dirName) ->
        # Create a directory in the cache.
        console.log "missing"
        return false

exports.FileCache = FileCache

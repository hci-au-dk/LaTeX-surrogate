fs = require 'fs'
https = require 'https'
FileCache = require './filecache'.FileCache

# Defines
REPOFILE = 'prepo.json'
TIMEOUT = 60 * 60 * 1000 # One hour in milliseconds

class ProjectRepo
    constructor: () ->
        # Load the repo from file - if it exists.
        try
            @repositories = JSON.parse fs.readFilesync(REPOFILE)
        catch error
            console.log 'Error loading repository info from file. Starting with an empty repo.'
            @repositories = {}
            
        # Create the file cache.
        @fileCache = new FileCache()
        
        # Register a timed event for cleanup.
        setInterval @cleanRepos, 10 * 60 * 1000
        
    cleanRepos: () ->
        now = new Date()
        delete_these = []
        for key of @repositories
            repo = @repositories[key]
            if now - repo.timestamp > TIMEOUT
                # Delete the repository from the cache.
                @fileCache.removeCache repo.cacheName
                
                # Add the repo to the delete_these array.
                delete_these.push key
        
        # Finally, remove the keys from the dict.
        for key in delete_these
            delete @repositories[key]
                
    createRepo: (host, port, owner, path, cb) ->
        # Create a filecache entry for the repo.
        # Create a cache path for the checkout.
        cacheName = owner + path.split('/').join('+')
        if not @fileCache.createCache cacheName
            cb 'Error creating cache dir', 500
            return        

        # The filecache has been created - we thus need to register the repo.
        @repositories[owner+path] = { cacheName: cacheName, timestamp : new Date() }
        
        # Check out the repo contents from the url.
        # Try to fetch the directory listing.
        options = {
            host: host,
            port: port,
            path: '/store/' + owner + path,
            method: 'GET'
        }
        request = https.request options, (res) =>
            if res.statusCode != 200
                console.log "Error requesting directory listing.", res.statusCode
                cb "Error requesting directory listing." + res.statusCode, 500
                return
                
            data = ''
            res.on 'data', (chunk) ->
                data += chunk
                
            res.on 'end', () =>
                dirListing = JSON.parse data

                fetchFiles = (files, callback) =>
                    item = files[0]
                    if item['is_dir']
                        # TODO: for now we ignore directories
                        callback files[1...]
                        return
                        
                    console.log 'Fetching file ' + files[0].path #DEBUG
                    options = {
                        host: host,
                        port: port,
                        path: '/store/' + owner + '/' + item.path,
                        method: 'GET'
                    }
                    request = https.request options, (res) =>
                        if res.statusCode != 200
                            console.log 'Error fetching file ' + item.path
                            cb 'Error fetching file ' + item.path, 500
                            return
                            
                        data = ''
                        res.on 'data', (chunk) ->
                            data += chunk
                            
                        res.on 'end', () =>
                            # Write the fetched file to the cache
                            if not @fileCache.writeFile cacheName, item.path.split('/')[-1..-1][0], data
                                console.log 'Error writing file to cache ' + item.path.split('/')[-1..-1][0]
                                cb 'Error while fetching files.', 500
                            else
                                console.log 'Successfully fetched ' + item.path #DEBUG
                                remainingFiles = files[1...]
                                if remainingFiles.length > 0
                                    callback remainingFiles, callback
                                else
                                    cb 'Successfully fetched all files.', 200
                    request.on 'error', (err) ->
                        console.log 'Error while fetching file.', err
                        cb 'Error fetching files.', 500
                    request.setHeader 'Cookie', @cookie
                    request.end()

                fetchFiles dirListing, fetchFiles

                #cb 'w00t!' #DEBUG
        request.on 'error', (err) ->
            console.log "Error requesting directory listing."
            cb "Error requesting directory listing.", 500
        console.log @cookie #DEBUG
        request.setHeader 'Cookie', @cookie
        request.end()
        

exports.FileCache = FileCache

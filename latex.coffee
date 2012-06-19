fs = require 'fs'
spawn = require('child_process').spawn

# Compile a LaTeX document. 'dir' points to the directory in the cache that
# contains the .tex files and 'cb' is a callback function that accepts two arguments:
# (error, data).
compile = (dir, cb) ->
    console.log 'compile!', dir
    # Read the .project file to get the project configuration.
    try
        config = JSON.parse(fs.readFileSync(dir + '/.project', 'utf8'))
    catch error
        console.log 'Error reading/parsing .project file in LaTeX folder.'
        cb 'Error reading/parsing .project file in LaTeX folder.', null
        return

    # Check that the .project file contains the needed keys.
    if not config.master? or not config.output?
        cb 'Invalid .project file in LaTeX project.', null
        return

    # Spawn the LaTeX compilation process.
    options = {
        cwd: dir,
        env: process.env,
        customFds: [-1, -1, -1]
    }
    args = [ '-interaction=nonstopmode', '-jobname=' + config.output, config.master ]
    pdflatex = spawn('pdflatex', args, options)

    stderrData = ''
    pdflatex.stderr.on 'data', (data) ->
        stderrData += data

    stdoutData = ''
    pdflatex.stdout.on 'data', (data) ->
        stdoutData += data

    pdflatex.on 'exit', (code) ->
        if code != 0
            cb 'pdflatex finished with error.', [stderrData, stdoutData]
        else
            cb null, dir + '/' + config.output + '.pdf'

exports.compile = compile
_         = require("lodash")
fs        = require("fs-extra")
path      = require("path")
check     = require("syntax-error")
coffee    = require("coffee-script")
Promise   = require("bluebird")
jsonlint  = require("jsonlint")
beautify  = require("js-beautify").html
pretty    = require("js-object-pretty-print").pretty
formatter = require("jsonlint/lib/formatter").formatter
cwd       = require("./cwd")

fs = Promise.promisifyAll(fs)

extensions = ".json .js .coffee .html .txt .png .jpg .jpeg .gif .tif .tiff .zip".split(" ")

queue = {}

lastCharacterIsNewLine = (str) ->
  str[str.length - 1] is "\n"

module.exports = {
  get: ->
    p       = path.join.apply(path, arguments)
    fixture = path.basename(p)

    ## if we have an extension go
    ## ahead adn read in the file
    if ext = path.extname(p)
      @parseFile(p, fixture, ext)
    else
      ## change this to first glob for
      ## the files, and if nothing is found
      ## throw a better error message
      tryParsingFile = (index) =>
        ext = extensions[index]

        if not ext
          throw new Error("No fixture file found with an acceptable extension. Searched in: #{p}")

        @fileExists(p + ext)
          .catch ->
            tryParsingFile(index + 1)
          .then ->
            @parseFile(p + ext, fixture, ext)

      Promise.resolve tryParsingFile(0)

  fileExists: (p) ->
    fs.statAsync(p).bind(@)

  parseFile: (p, fixture, ext) ->
    if queue[p]
      Promise.delay(1).then =>
        @parseFile(p, fixture, ext)
    else
      queue[p] = true

      cleanup = ->
        delete queue[p]

      @fileExists(p)
        .catch (err) ->
          throw new Error("No fixture exists at: #{p}")
        .then ->
          @parseFileByExtension(p, fixture, ext)
        .then (ret) ->
          cleanup()

          return ret
        .catch (err) ->
          cleanup()

          throw err

  parseFileByExtension: (p, fixture, ext) ->
    ext ?= path.extname(fixture)

    switch ext
      when ".json"   then @parseJson(p, fixture)
      when ".js"     then @parseJs(p, fixture)
      when ".coffee" then @parseCoffee(p, fixture)
      when ".html"   then @parseHtml(p, fixture)
      when ".txt"    then @parseText(p, fixture)
      when ".png", ".jpg", ".jpeg", ".gif", ".tif", ".tiff", ".zip"
        @parseBase64(p, fixture)
      else
        throw new Error("Invalid fixture extension: '#{ext}'. Acceptable file extensions are: #{extensions.join(", ")}")

  parseJson: (p, fixture) ->
    fs.readFileAsync(p, "utf8")
      .bind(@)
      .then (str) ->
        ## format the json
        formatted = formatter.formatJson(str, "  ")

        ## if we didnt change then return the str
        if formatted is str
          return str
        else
          ## if last character is a new line
          ## then append this to the formatted str
          if lastCharacterIsNewLine(str)
            formatted += "\n"
          ## write the file back even if there were errors
          ## so we write back the formatted version of the str
          fs.writeFileAsync(p, formatted).return(formatted)
      .then(jsonlint.parse)
      .catch (err) ->
        throw new Error("'#{fixture}' is not valid JSON.\n#{err.message}")

  parseJs: (p, fixture) ->
    fs.readFileAsync(p, "utf8")
      .bind(@)
      .then (str) ->
        try
          obj = eval("(" + str + ")")
        catch e
          err = check(str, fixture)
          throw err if err
          throw e

        return obj
      .then (obj) ->
        str = pretty(obj, 2)
        fs.writeFileAsync(p, str).return(obj)
      .catch (err) ->
        throw new Error("'#{fixture}' is not a valid JavaScript object.#{err.toString()}")

  parseCoffee: (p, fixture) ->
    dc = process.env.NODE_DISABLE_COLORS

    process.env.NODE_DISABLE_COLORS = "0"

    fs.readFileAsync(p, "utf8")
      .bind(@)
      .then (str) ->
        str = coffee.compile(str, {bare: true})
        eval(str)
      .then (obj) ->
        str = pretty(obj, 2)
        fs.writeFileAsync(p, str).return(obj)
      .catch (err) ->
        throw new Error("'#{fixture} is not a valid CoffeeScript object.\n#{err.toString()}")
      .finally ->
        process.env.NODE_DISABLE_COLORS = dc

  parseHtml: (p, fixture) ->
    fs.readFileAsync(p, "utf8")
      .bind(@)
      .then (str) ->
        html = beautify str, {
          indent_size: 2
          extra_liners: []
        }

        if lastCharacterIsNewLine(str)
          html += "\n"

        fs.writeFileAsync(p, html).return(html)

  parseText: (p, fixture) ->
    fs.readFileAsync(p, "utf8")
      .bind(@)

  parseBase64: (p, fixture) ->
    fs.readFileAsync(p, "base64")
      .bind(@)

}


local typedefs = require "kong.db.schema.typedefs"
local xmlgeneral   = require("kong.plugins.lua-xml-handling-lib.xmlgeneral")

return {
  name = "xml-response-3-transform-xslt-after",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { xsltTransformAfter = { type = "string", required = true }, },
        },
    }, },
  },
}
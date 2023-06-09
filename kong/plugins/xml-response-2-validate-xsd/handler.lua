-- handler.lua
local plugin = {
    PRIORITY = 70,
    VERSION = "1.0.0",
  }

-----------------------------------------------------------------------------------------
-- Executed when all response headers bytes have been received from the upstream service
-----------------------------------------------------------------------------------------
function plugin:access(plugin_conf)
  
  -- Enables buffered proxying, which allows plugins to access Service body and response headers at the same time
  -- Mandatory calling 'kong.service.response.get_raw_body()' in 'header_filter' phase
  kong.service.request.enable_buffering()
end

-----------------------------------------------------------------------------------------
-- Executed when all response headers bytes have been received from the upstream service
-----------------------------------------------------------------------------------------
function plugin:header_filter(plugin_conf)
  local errMessage
  local soapEnvelope
  local xmlgeneral = require("kong.plugins.lua-xml-handling-lib.xmlgeneral")
  
    -- In case of error set by previous plugin, we don't do anything to avoid an issue.
  -- If we call get_raw_body (), without calling request.enable_buffering(), it will raise an error and 
  -- it happens when a previous plugin called kong.response.exit(): in this case all 'header_filter' and 'body_filter'
  -- are called (and the 'access' is not called which enables the enable_buffering())
  if kong.ctx.shared.xmlSoapHandlingFault and 
     kong.ctx.shared.xmlSoapHandlingFault.error then
    kong.log.notice("A pending error has been set by previous plugin: we do nothing in this plugin")
    return
  end
  
  -- If a previous Response plugin modified the soapEnvelope we retrieve it with 'kong.ctx.shared'
  -- because we are unable to call 'kong.response.get_raw_body' (which is not available in 'header_filter')
  if  kong.ctx.shared.xmlSoapHandlingFault and
      kong.ctx.shared.xmlSoapHandlingFault.soapEnvelope then
    soapEnvelope = kong.ctx.shared.xmlSoapHandlingFault.soapEnvelope
  -- There is no previous Response plugin
  else
    -- Get SOAP envelope from the Response backend API
    soapEnvelope = kong.service.response.get_raw_body ()
  end
  
  -- There is no SOAP envelope (or Body content) so we don't do anything
  if not soapEnvelope then
    kong.log.notice("The Body is 'nil'")
    return
  end

  -- If there is a SOAP envelope in the Response and the plugin is defined with XSD SOAP schema
  if soapEnvelope and plugin_conf.xsdSoapSchema then
    -- Validate the SOAP XML with its schema
    errMessage = xmlgeneral.XMLValidateWithXSD (plugin_conf, 0, soapEnvelope, plugin_conf.xsdSoapSchema)
    
    if errMessage ~= nil then
      local soapFaultBody = xmlgeneral.formatSoapFault(xmlgeneral.ResponseTextError .. xmlgeneral.SepTextError .. xmlgeneral.XSDError, 
                                                      errMessage)
      
      -- Return a Fault code to Client
      -- the Body content (with the detailed error message) will be changed by 'body_filter' phase
      kong.response.set_status(xmlgeneral.HTTPCodeSOAPFault)
      kong.response.set_header("Content-Length", #soapFaultBody)
      
      -- Set the Global Fault Code to Request and Response XLM/SOAP plugins 
      -- It prevents to apply XML/SOAP handling whereas there is already an error
      kong.ctx.shared.xmlSoapHandlingFault = {
        error = true,
        priority = plugin.PRIORITY,
        soapEnvelope = soapFaultBody
      }
    end
  end
  
  -- If there is no error and If there is a SOAP envelope and If the plugin is defined with XSD API schema
  if not errMessage and soapEnvelope and plugin_conf.xsdApiSchema then
  
    -- Validate the API XML (included in the <soap:envelope>) with its schema
    errMessage = xmlgeneral.XMLValidateWithXSD (plugin_conf, 2, soapEnvelope, plugin_conf.xsdApiSchema)
    
    if errMessage ~= nil then
      local soapFaultBody = xmlgeneral.formatSoapFault(xmlgeneral.ResponseTextError .. xmlgeneral.SepTextError .. xmlgeneral.XSDError, 
                                                      errMessage)
      
      -- Return a Fault code to Client
      -- the Body content (with the detailed error message) will be changed by 'body_filter' phase
      kong.response.set_status(xmlgeneral.HTTPCodeSOAPFault)
      kong.response.set_header("Content-Length", #soapFaultBody)
      
      -- Set a Global Fault Code to Request and Response XLM/SOAP plugins 
      -- It prevents to apply XML/SOAP handling whereas there is already an error
            -- Set the Global Fault Code to Request and Response XLM/SOAP plugins 
      -- It prevents to apply XML/SOAP handling whereas there is already an error
      kong.ctx.shared.xmlSoapHandlingFault = {
        error = true,
        priority = plugin.PRIORITY,
        soapEnvelope = soapFaultBody
      }
    end
  end
end

------------------------------------------------------------------------------------------------------------------
-- Executed for each chunk of the response body received from the upstream service.
-- Since the response is streamed back to the client, it can exceed the buffer size and be streamed chunk by chunk.
-- This function can be called multiple times
------------------------------------------------------------------------------------------------------------------
function plugin:body_filter(plugin_conf)

  -- If there is a pending error we don't do anything except for the Plugin itself
  if  kong.ctx.shared.xmlSoapHandlingFault        and
      kong.ctx.shared.xmlSoapHandlingFault.error  and 
      kong.ctx.shared.xmlSoapHandlingFault.priority ~= plugin.PRIORITY then
    kong.log.notice("A pending error has been set by previous plugin: we do nothing in this plugin")
    return
  end

  local xmlgeneral = require("kong.plugins.lua-xml-handling-lib.xmlgeneral")
  -- Get modified SOAP envelope set by the plugin itself on 'header_filter'
  if  kong.ctx.shared.xmlSoapHandlingFault  and
        kong.ctx.shared.xmlSoapHandlingFault.priority == plugin.PRIORITY then
  
    if kong.ctx.shared.xmlSoapHandlingFault.soapEnvelope then
      kong.response.set_raw_body(kong.ctx.shared.xmlSoapHandlingFault.soapEnvelope)
    end
  end

end
  
return plugin
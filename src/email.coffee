


############################################################################################################
# njs_util                  = require 'util'
njs_path                  = require 'path'
# njs_fs                    = require 'fs'
# njs_url                   = require 'url'
#...........................................................................................................
OPTIONS                   = require 'coffeenode-options'
TYPES                     = require 'coffeenode-types'
TRM                       = require 'coffeenode-trm'
rpr                       = TRM.rpr.bind TRM
badge                     = 'USERDB/core'
log                       = TRM.get_logger 'plain',     badge
info                      = TRM.get_logger 'info',      badge
whisper                   = TRM.get_logger 'whisper',   badge
alert                     = TRM.get_logger 'alert',     badge
debug                     = TRM.get_logger 'debug',     badge
warn                      = TRM.get_logger 'warn',      badge
help                      = TRM.get_logger 'help',      badge
echo                      = TRM.echo.bind TRM
#...........................................................................................................
app_info                  = OPTIONS.get_app_info()
nodemailer                = require 'nodemailer'
email_options             = require njs_path.join app_info[ 'user-home' ], 'coffeenode-mail-options.json'


send_email = ( email ) ->
  info "sending mail..."
  smtpTransport = nodemailer.createTransport 'SMTP', email_options
  smtpTransport.sendMail email, ( error, response ) ->
    if error?
      warn error
    else
      info "Message sent: " + response.message
    smtpTransport.close()

email =
  from:       "Node Mailer <wolfgang.lipp@gmail.com>" # sender address
  # to:         "Your Name <wolfgang.lipp@gmail.com>" # comma separated list of receivers
  to:         "Your Name <paragate@gmx.net>" # comma separated list of receivers
  subject:    "Hello ✔" # Subject line
  text:       "Hello world 𪜃" # plaintext body

send_email email

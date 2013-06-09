crypto    = require('crypto')
algorithm = "aes256"
key       = process.env.ENCRYPTION_KEY
key2      = process.env.ENCRYPTION_KEY2
nest      = require 'unofficial-nest-api'
mongoose  = require('mongoose')
Schema    = mongoose.Schema
google    = require 'googleapis'

# Schema Setup
UserSchema = new Schema(
  email:
    type: String
    index: true
  firstName: String
  lastName: String

  gid: String

  _token: String
  _token_type: String
  _refresh_token: String

)


UserSchema.virtual('password')
  .get( () -> this._password )
  .set( (pass) ->
    @.setPassword(pass)
    @._password = pass
  )



UserSchema.virtual('token')
  .get( ()->
    if @._token
      return JSON.parse(@.decryptSecure @._token)
    undefined
  )
  .set( (obj) ->
    this._token = @.encryptSecure JSON.stringify(obj)
  )

# Dont wrap, b/c known to be one of a set of known values
# deceases security of encryption
UserSchema.virtual('token_type')
  .get( ()->
    @._token_type
  )
  .set( (obj) ->
    this._token_type = obj
  )

UserSchema.virtual('refresh_token')
  .get( ()->
    if @._refresh_token
      return JSON.parse(@.decryptSecure @._refresh_token)
    undefined
  )
  .set( (obj) ->
    this._refresh_token = @.encryptSecure JSON.stringify(obj)
  )


UserSchema.method('encryptSecure', (text) ->
  cipher = crypto.createCipher algorithm, key
  cipher.update(text, 'utf8', 'hex') + cipher.final('hex')
)
UserSchema.method('decryptSecure', (encrypted)->
  decipher = crypto.createDecipher algorithm, key
  decipher.update(encrypted, 'hex', 'utf8') + decipher.final('utf8')
)


UserSchema.virtual('id')
  .get( () -> this._id.toHexString() )

UserSchema.virtual('name')
  .get( () -> "#{@.firstName} #{@.lastName}".trim() )
  .set( (fullName) ->
    p = fullName.split ' '
    @.firstName = p[0]
    @.lastName = p[1]
  )

UserSchema.method('credentials', () ->
    oauth2Client = new google.OAuth2Client(
      process.env.GOOGLE_CLIENT_ID,
      process.env.GOOGLE_CLIENT_SECRET,
      process.env.GOOGLE_REDIRECT_URL);
    oauth2Client.credentials =
      token_type: @.token_type
      access_token: @.token,
      refresh_token: @.refresh_token
    oauth2Client
  )



UserSchema.pre 'save', (next) ->
  @.modified = Date.now()
  next()



# Exports
exports.UserSchema = module.exports.UserSchema = UserSchema
exports.boot = module.exports.boot = (app) ->
  mongoose.model 'User', UserSchema
  app.models.User = mongoose.model 'User'



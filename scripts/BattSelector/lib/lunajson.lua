local newdecoder = require 'lib.decoder'
local newencoder = require 'lib.encoder'
local sax = require 'lib.sax'

-- If you need multiple contexts of decoder and/or encoder,
-- you can require lunajson.decoder and/or lunajson.encoder directly.
return {
	decode = newdecoder(),
	encode = newencoder(),
	newparser = sax.newparser,
	newfileparser = sax.newfileparser,
}

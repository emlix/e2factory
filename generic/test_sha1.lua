require("sha1")

--[[
Test Vectors (from FIPS PUB 180-1)
"abc"
  A9993E36 4706816A BA3E2571 7850C26C 9CD0D89D
"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
  84983E44 1C3BD26E BAAE4AA1 F95129E5 E54670F1
A million repetitions of "a"
  34AA973C D4C4DAA4 F61EEB2B DBAD2731 6534016F
--]]

local c, r
c = sha1.sha1_init()
c:update("abc")
r = c:final()
assert(r == "A9993E364706816ABA3E25717850C26C9CD0D89D")

c = sha1.sha1_init()
c:update("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
r = c:final()
assert(r == "84983E441C3BD26EBAAE4AA1F95129E5E54670F1")

c = sha1.sha1_init()
for i=1, 1000000, 1 do
	c:update("a")
end
r = c:final(c)
assert(r == "34AA973CD4C4DAA4F61EEB2BDBAD27316534016F")

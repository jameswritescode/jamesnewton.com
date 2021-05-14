# frozen_string_literal: true

# WARN: I don't know if this stuff is actually any good, but I'm using it as part of experimenting with graphql-ruby's
#       object identification https://graphql-ruby.org/schema/object_identification.html
class EncryptionService
  attr_reader :cipher

  def initialize
    @cipher = OpenSSL::Cipher.new('aes-256-cbc')
  end

  def encrypt(input)
    cipher.encrypt
    setup
    Base64.encode64(result(input)).rstrip
  end

  def decrypt(input)
    cipher.decrypt
    setup
    result(Base64.decode64(input))
  end

  private

  def result(input)
    cipher.update(input) + cipher.final
  end

  def setup
    cipher.iv = Rails.application.credentials[:encryption_service_iv]
    cipher.key = Rails.application.credentials[:encryption_service_key]
  end
end

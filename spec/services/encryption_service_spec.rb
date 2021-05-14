# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EncryptionService do
  it 'encrypts and decrypts' do
    output = described_class.new.encrypt('input')

    expect(described_class.new.decrypt(output)).to eq 'input'
  end
end

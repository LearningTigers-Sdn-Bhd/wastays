require 'rails_helper'

RSpec.describe CancellationPolicyTemplate, type: :model do
  it 'builds a valid record from factory' do
    expect(build(:cancellation_policy_template)).to be_valid
  end
end

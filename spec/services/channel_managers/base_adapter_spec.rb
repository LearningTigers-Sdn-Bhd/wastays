require "rails_helper"

RSpec.describe ChannelManagers::BaseAdapter do
  it "defines the interface" do
    adapter = described_class.new(hotel: double)
    expect { adapter.onboard_hotel }.to raise_error(NotImplementedError)
  end
end

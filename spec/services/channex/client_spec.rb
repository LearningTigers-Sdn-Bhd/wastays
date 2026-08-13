require 'rails_helper'

RSpec.describe Channex::Client do
  let(:api_key) { 'test_api_key' }
  let(:client) { described_class.new(api_key: api_key) }

  describe '#get' do
    it 'makes a GET request with correct headers' do
      stub_request(:get, "https://staging.channex.io/api/v1/properties")
        .with(headers: { 'user-api-key' => api_key, 'Content-Type' => 'application/json' })
        .to_return(status: 200, body: { data: [] }.to_json)

      response = client.get('/properties')
      expect(response['data']).to eq([])
    end
  end

  describe '#post' do
    it 'makes a POST request with correct body' do
      payload = { property: { name: 'Test' } }
      stub_request(:post, "https://staging.channex.io/api/v1/properties")
        .with(body: payload.to_json)
        .to_return(status: 201, body: { data: { id: '123' } }.to_json)

      response = client.post('/properties', payload)
      expect(response['data']['id']).to eq('123')
    end
  end

  describe 'error handling' do
    it 'returns error hash on failure' do
      stub_request(:get, "https://staging.channex.io/api/v1/properties")
        .to_return(status: 401, body: { errors: 'Unauthorized' }.to_json)

      response = client.get('/properties')
      expect(response[:error]).to eq('Channel Manager API error: 401')
      expect(response[:details]).to eq('Unauthorized')
    end

    it 'marks only throttling and server responses as retryable' do
      [ 429, 503 ].each do |status|
        stub_request(:get, "https://staging.channex.io/api/v1/properties")
          .to_return(status: status, body: { errors: 'Try later' }.to_json)

        expect(client.get('/properties')[:retryable]).to be(true)
      end

      stub_request(:get, "https://staging.channex.io/api/v1/properties")
        .to_return(status: 422, body: { errors: 'Invalid input' }.to_json)

      expect(client.get('/properties')[:retryable]).to be(false)
    end
  end
end

# frozen_string_literal: true

require "open3"

# Which providers a live fixture run can actually reach.
#
# The concierge takes its key from the hotel row, but a fixture hotel is built
# by a factory in an empty test database, so a live run has to be told a real
# key from somewhere. That somewhere is the platform key the superadmin already
# filled in at /admin/integrations -- the same AppConfig rows the observation
# deck and the embedding service read.
#
# Those rows live in the development database, and they are encrypted with the
# development environment's keys (config/environments/development.rb:73), which
# the test environment deliberately does not share. Reading the row across a
# second connection therefore gets ciphertext nothing here can open. So the
# lookup asks development to read its own data, once per run, and takes the
# plaintext back. ENV wins when it is set, which is how CI or a throwaway key
# gets in without touching anybody's database.
#
# A provider with no key is not a failure. It is a row in the report that says
# nobody measured it.
module AiConciergeEval
  module LiveProviders
    # AppConfig keys the admin page writes. Note the concierge calls it
    # "claude" and the platform config calls it "anthropic": one product, two
    # names, and both are already in the schema.
    KEY_NAMES = {
      "openai" => "openai_api_key",
      "claude" => "anthropic_api_key",
      "gemini" => "gemini_api_key"
    }.freeze

    Provider = Struct.new(:name, :key, :model, keyword_init: true)

    module_function

    # Providers that have a key, in the order the report lists them.
    def configured
      @configured ||= KEY_NAMES.keys.filter_map do |name|
        key = key_for(name)
        next if key.blank?

        Provider.new(name: name, key: key, model: Hotel::AI_CONCIERGE_MODEL_NAMES.fetch(name))
      end
    end

    # Providers that have no key, so the report can say so out loud rather than
    # leaving a table that looks complete.
    def unconfigured
      KEY_NAMES.keys - configured.map(&:name)
    end

    def key_for(name)
      ENV["CONCIERGE_LIVE_#{name.upcase}_KEY"].presence || platform_keys[KEY_NAMES.fetch(name)]
    end

    def platform_keys
      @platform_keys ||= read_platform_keys
    end

    # One boot of the development environment, whose only job is to decrypt
    # three rows. Nothing is written, and the plaintext goes no further than
    # this process.
    def read_platform_keys
      script = <<~RUBY
        AppConfig.where(key: #{KEY_NAMES.values.inspect}).each do |config|
          puts "\#{config.key}\t\#{config.value}"
        end
      RUBY

      output, status = Open3.capture2({ "RAILS_ENV" => "development" }, "bin/rails", "runner", script, chdir: Rails.root.to_s)
      return {} unless status.success?

      output.lines.filter_map { |line| line.chomp.split("\t", 2) }.to_h { |key, value| [ key, value.to_s ] }
    rescue StandardError
      {}
    end
  end
end

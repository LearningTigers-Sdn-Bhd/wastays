# frozen_string_literal: true

module FrozenTimeHelpers
  def with_frozen_time(value, &block)
    time = resolve_frozen_time(value)
    return travel_to(time) unless block

    travel_to(time, &block)
  end

  private

  def resolve_frozen_time(value)
    value = instance_exec(&value) if value.respond_to?(:call)
    return Time.current.change(hour: 12, min: 0, sec: 0, usec: 0) if value == :business_day

    value
  end
end

RSpec.configure do |config|
  config.include FrozenTimeHelpers

  config.after(:each) do
    travel_back
  end

  config.around(:each) do |example|
    frozen_time = example.metadata[:frozen_time]

    if frozen_time
      example.example_group_instance.with_frozen_time(frozen_time) { example.run }
    else
      example.run
    end
  end
end

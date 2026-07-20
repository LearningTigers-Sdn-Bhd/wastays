# frozen_string_literal: true

module StayView
  module Immutable
    module_function

    def array(value)
      Array(value).map { |item| value(item) }.freeze
    end

    def hash(value)
      value.to_h.each_with_object({}) do |(key, item), result|
        result[key] = value(item)
      end.freeze
    end

    def value(item)
      case item
      when Array then array(item)
      when Hash then hash(item)
      else item.freeze
      end
    end
  end
end

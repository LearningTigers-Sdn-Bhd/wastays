# frozen_string_literal: true

# Recipe for service return values.
#
# Services used to answer with OpenStruct, which replies to every message. A
# misspelled read — result.sucess? — came back nil, which is falsy, so a failure
# read as a success and nothing said so. In money code that is a silent wrong
# answer.
#
# A Data class with the same member names is a drop-in for readers and raises
# NoMethodError on anything else:
#
#   module Folios
#     Result = ApplicationResult.define(:folio)
#   end
#
#   Folios::Result.success(folio: folio)
#   Folios::Result.failure("Folio is already closed.", folio: @folio)
#
# Data demands every member at construction, so both builders nil-fill whatever
# the caller leaves out. That keeps a success from having to name error, and a
# failure from having to name the members it has no value for.
module ApplicationResult
  def self.define(*members)
    Data.define(:"success?", :error, *members) do
      def self.success(**attributes)
        build(**attributes, "success?": true, error: nil)
      end

      def self.failure(error, **attributes)
        build(**attributes, "success?": false, error: error)
      end

      def self.build(**attributes)
        new(**members.to_h { |member| [ member, nil ] }.merge(attributes))
      end
    end
  end
end

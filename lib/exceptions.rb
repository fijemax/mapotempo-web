require 'singleton'

module Exceptions
  class LoopError < StandardError; end
  class JobInProgressError < StandardError; end

  ############################################
  #  Base class for nested model validations #
  ############################################
  class BaseNestedModelErrors < StandardError
    attr_reader :object
    def initialize(val, id, hash_for_nested = {})
      super(message) #keep it super simple
      handle_nested_hash(hash_for_nested)
      @object = {value: val, visit_id: id} # Hash returned in view to show further information (User Friendly)
    end

    def handle_nested_hash(hash_for_nested)
      ensure_params = (!hash_for_nested.empty? && hash_for_nested.is_a?(Hash))
      ensure_params && NestedAttributesManager.instance.add_nested_errors(hash_for_nested) # Singleton pattern using "instance" to keep low usage
    end
  end

  # Class errors # | ADD new nested handlers here |
  class NegativeErrors     < BaseNestedModelErrors; end
  class CloseAndOpenErrors < BaseNestedModelErrors; end

  ############################################
  #   Nested Manager, handle display errors  #
  ############################################
  class NestedAttributesManager
    include Singleton
    attr_accessor :nested_hash_error, :hash_size

    def initialize
      @nested_hash_error = { }
      @hash_size         = 0
    end

    def add_nested_errors(nested_hash)
      record = model_record(nested_hash)

      if @nested_hash_error.key? nested_hash[:nested_attr]
        push_uniq_record(record, nested_hash[:nested_attr])
      else
        @nested_hash_error[nested_hash[:nested_attr]] = [record]
      end
      @hash_size += 1
    end

    def get_hash_for(key, id)
      resp = nil
      if @nested_hash_error[key] && !@nested_hash_error[key].empty?
        visit_negative = @nested_hash_error[key].select { |visit_error| visit_error[:id] == id }[0]
        resp = @nested_hash_error[key].delete(visit_negative)
      end
      resp
    end

    private

    def model_record(hash_to_be_modeled)
      nested_attr = hash_to_be_modeled[:nested_attr]
      {
                id: hash_to_be_modeled[:record][:id],
       nested_attr: hash_to_be_modeled[:record][nested_attr]
      }
    end

    def push_uniq_record(new_record, key)
      valid = true
      @nested_hash_error[key].each_with_index do |element, index|
          next unless element[:id] == new_record[:id]
          valid = false
          @nested_hash_error[key][index][:nested_attr] = new_record[:nested_attr] # Update value if needed
          break
      end
      @nested_hash_error[key].push(new_record) if valid
    end
  end
end

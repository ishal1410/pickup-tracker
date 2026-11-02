# Shared by Pickup and Device: status only moves along the model's TRANSITIONS
# map, one step at a time. Anything not in the map is refused.
module ForwardOnly
  extend ActiveSupport::Concern

  included do
    # Guards every write, including console or seed updates.
    validate :follows_transitions, on: :update
  end

  private
    # Guards the action methods. Unlike the validation, it also refuses a
    # repeat (sanitized -> sanitized), so a second sanitize can't swap the method.
    # with_lock reloads the row under a lock, so two concurrent requests can't
    # both pass the check on a stale in-memory status.
    def move_to(new_status, **attrs)
      with_lock do
        unless self.class::TRANSITIONS.fetch(status, []).include?(new_status)
          errors.add(:status, "can't go from #{status} to #{new_status}")
          next false
        end
        update(status: new_status, **attrs)
      end
    end

    def follows_transitions
      return unless status_changed?
      unless self.class::TRANSITIONS.fetch(status_was, []).include?(status)
        errors.add(:status, "can't go from #{status_was} to #{status}")
      end
    end
end

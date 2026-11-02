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
    # at: backdates the move (demo sample data); it stamps the history entry.
    def move_to(new_status, at: Time.current, **attrs)
      with_lock do
        from = status
        unless self.class::TRANSITIONS.fetch(from, []).include?(new_status)
          errors.add(:status, "can't go from #{from} to #{new_status}")
          next false
        end
        next false unless update(status: new_status, **attrs)
        # ADR-011: the device audit trail is written here and nowhere else, in
        # the same locked transaction as the move. Pickups keep no events.
        events.create!(from_status: from, to_status: new_status, created_at: at) if respond_to?(:events)
        true
      end
    end

    def follows_transitions
      return unless status_changed?
      unless self.class::TRANSITIONS.fetch(status_was, []).include?(status)
        errors.add(:status, "can't go from #{status_was} to #{status}")
      end
    end
end

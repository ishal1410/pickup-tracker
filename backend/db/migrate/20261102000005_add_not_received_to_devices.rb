# ADR-009: a listed serial that never arrived ends as "not_received". It is never
# sanitized, so it belongs on the "no method, no time" side of the fields check.
class AddNotReceivedToDevices < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :devices, name: "devices_status_allowed"
    remove_check_constraint :devices, name: "devices_sanitized_fields"
    add_check_constraint :devices,
      "status IN ('expected', 'received', 'not_received', 'sanitized', 'resold', 'donated', 'recycled')",
      name: "devices_status_allowed"
    add_check_constraint :devices,
      "CASE WHEN status IN ('expected', 'received', 'not_received') THEN sanitization_method IS NULL AND sanitized_at IS NULL " \
      "ELSE sanitization_method IS NOT NULL AND sanitized_at IS NOT NULL END",
      name: "devices_sanitized_fields"
  end

  def down
    remove_check_constraint :devices, name: "devices_status_allowed"
    remove_check_constraint :devices, name: "devices_sanitized_fields"
    add_check_constraint :devices, "status IN ('expected', 'received', 'sanitized', 'resold', 'donated', 'recycled')", name: "devices_status_allowed"
    add_check_constraint :devices,
      "CASE WHEN status IN ('expected', 'received') THEN sanitization_method IS NULL AND sanitized_at IS NULL " \
      "ELSE sanitization_method IS NOT NULL AND sanitized_at IS NOT NULL END",
      name: "devices_sanitized_fields"
  end
end

-- bcc-doorlocks item definitions for feather-inventory.
-- Safe to run more than once: an existing item keeps its ID and settings.
-- bcc-craft defines the same lockpick; whichever file runs first creates it.
-- Apply once, then restart feather-inventory and bcc-doorlocks.

INSERT INTO `items`
    (`name`, `display_name`, `description`, `max_quantity`, `max_stack_size`, `weight`, `usable`, `category_id`, `type`, `instance_mode`)
SELECT 'lockpick', 'Lockpick', 'Used to pick locks. Breaks on a failed attempt.', 20, 10, 0.1, 0,
    (SELECT `id` FROM `categories` WHERE `name` = 'tools'), 'item_item', 'stack'
WHERE NOT EXISTS (SELECT 1 FROM `items` WHERE `name` = 'lockpick');

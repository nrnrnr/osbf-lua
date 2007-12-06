--- returns table of user-editable configuration parameters

return {
  -- command password
  pwd = "your_password_here", -- no spaces allowed

  -- classes of email received
  --   1. Table for each class name of
  --        sfid        -- unique lowercase letter to identify class (required)
  --        sure        -- Subject: tag when mail definitely classified (default empty)
  --        unsure      -- Subject: tag when mail in reinforcement zone (default '?')
  --        train_below -- confidence below which training is recommended (default 20)
  --        conf_boost  -- a number added to confidence for this class (default 0)
  --        resend      -- if this message is trained, resend it with new headers
  classes = {
    ham  = { sfid = 'h', sure = '',   unsure = '+', train_below = 20 },
    spam = { sfid = 's', sure = '--', unsure = '-', train_below = 20, resend = false },
  },

  -- -- alternative classification
  -- classes = {
  --   spam      = { sure = '--', unsure = '-', sfid = 's', train_below = 20,
  --                 resend = false
  --               },
  --   personal  = { sfid = 'p', sure = '',   unsure = '+', train_below = 10 },
  --   ecommerce = { sfid = 'c', sure = '$$', unsure = '$', train_below = 20 },
  --   work      = { sfid = 'w', sure = '',   unsure = 'w', train_below = 20 },
  -- }

  -- put tags on subject line?
  tag_subject     = true,

  -- training result subjects: used in string.format(string, class)
  -- can be specialized to each class as needed.
  trained_as_subject = { default = "Trained as %s" },
  training_not_necessary_single = "Training not necessary: score = %s is " ..
                                  "out of learning region %s",
  training_not_necessary_multi = "Training not necessary: scores = %s are " ..
                                  "out of learning regions %s",
  

  -- prefix of each header added to the message; by changing prefix,
  -- you can filter the same message with multiple instances of OSBF-Lua
  header_prefix = "X-OSBF-Lua", 
  header_suffixes = {
    summary = "Score",
    class = "Class",
    needs_training = "Train",
    confidence = "Confidence",
  },

  -- To disable sfids, make false.
  use_sfid     = true,

  -- SFID rightid - change it to personalize for your site.
  rightid        = "spamfilter.osbf.lua",

  -- In which headers to insert the SFID? Uncomment exactly one of them:
  --insert_sfid_in  = {"references"},
  --insert_sfid_in  = {"message-id"},
  insert_sfid_in  = {"references", "message-id"},

  -- log options
  save_for_training = true,  -- save msg for later training
  log_incoming      = true,  -- log all incoming messages
  log_learned       = true,  -- log learned messages
  log_dir           = "log", -- relative to the user osbf-lua dir

  -- If use_sfid_subdir is true, messages cached for later training
  -- are saved under a subdir under log_dir, formed by the day of
  -- the month and the time the message arrived (DD/HH), to avoid excessive
  -- files per dir. The subdirs must be created before you enable this option.
  use_sfid_subdir = false,

  -- Count classifications? To turn off, set to false.
  count_classifications = true,

  -- This option specifies that the original message will be written to stdout
  -- after a training, with the correct tag. To have the original behavior,
  -- that is, just a report message, comment this option out.
  training_output = "message",

  -- Language to use in the cache-report training message.
  -- Default of true uses the user's locale; otherwise
  -- we understand 'en_US' and 'pt_BR'.
  report_locale = true,

  -- Command to send pre-formatted command messages.
  -- The %s in the command will be replaced with the name
  -- of a file containing the pre-formatted
  -- message to be sent.
  mail_cmd = "/usr/lib/sendmail -it < %s",

  -- Limit on the number of messages in a single cache report.
  cache_report_limit = 50,

  -- Option to set what to order sfids by in cache report
  -- Valid values are 'date' and 'confidence'
  cache_report_order_by = "confidence",

  -- Order of messages in cache report.
  -- '<' => ascending; '>' => descending
  cache_report_order = "<",

  -- Address to send command-messages to
  command_address = "",

}


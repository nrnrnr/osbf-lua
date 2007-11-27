--- returns table of user-editable configuration parameters


local threshold = 20 -- low score range, or reinforcement zone,  
                     -- around min_pR_success. Use 20            
                     -- during the pre-training phase for better 
                     -- accuracy and reduce to 10 or less later, 
                     -- for less burden with daily trainings.    

return {
  -- command password
  pwd = "your_password_here", -- no spaces allowed

  -- XXX change 'threshold' to 'train_below' everywhere it makes sense

  -- classes of email received
  --   1. Table for each class name of
  --        sfid      -- unique lowercase letter to identify class (required)
  --        sure      -- Subject: tag when mail definitely classified (default empty)
  --        unsure    -- Subject: tag when mail in reinforcement zone (default '?')
  --        threshold -- pR below which training is assumed needed (default 20)
  --        pR_boost  -- a number added to pR for this class (default 0)
  --        resend    -- if this message is trained, resend it with new headers
  -- XXXX needs new names 'train_below' and 'confidence_boost'
  classes = {
    ham  = { sfid = 'h', sure = '',   unsure = '+', threshold = threshold },
    spam = { sfid = 's', sure = '--', unsure = '-', threshold = threshold,
             resend = false },
  },

  -- -- alternative classification
  -- classes = {
  --   spam      = { sure = '--', unsure = '-', sfid = 's', threshold = threshold,
  --                 resend = false
  --               },
  --   personal  = { sfid = 'p', sure = '',   unsure = '+', threshold = 10 },
  --   ecommerce = { sfid = 'c', sure = '$$', unsure = '$', threshold = threshold },
  --   work      = { sfid = 'w', sure = '',   unsure = 'w', threshold = threshold },
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
    score = "Score",
    class = "Class",
    needs_training = "Train",
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

  -- Set remove_body_threshold to the score below which you want the
  -- message body removed. Use this option after you have well trained
  -- databases:
  --remove_body_threshold = -2 * threshold,
  remove_body_threshold = false,

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


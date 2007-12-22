/*
 *  osbf_stats.c 
 *  
 *  This software is licensed to the public under the Free Software
 *  Foundation's GNU GPL, version 2.  You may obtain a copy of the
 *  GPL by visiting the Free Software Foundations web site at
 *  www.fsf.org, and a copy is included in this distribution.  
 *
 * Copyright 2005, 2006, 2007 Fidelis Assis, all rights reserved.
 * Copyright 2007 Norman Ramsey, all rights reserved.
 * Copyright 2005, 2006, 2007 Williams Yerazunis, all rights reserved.
 *
 * Read the HISTORY_AND_AGREEMENT for details.
 */

#include <string.h>

#include "osbflib.h"

/*****************************************************************/

void
osbf_stats (const CLASS_STRUCT *class, STATS_STRUCT * stats,
	    OSBF_HANDLER *h, int verbose)
{

  uint32_t i = 0;

  uint32_t used_buckets = 0, unreachable = 0;
  uint32_t max_chain = 0, num_chains = 0;
  uint32_t max_count = 0, first_chain_len = 0;
  uint32_t max_displacement = 0, chain_len_sum = 0;

  uint32_t chain_len = 0, count;

  OSBF_BUCKET_STRUCT *buckets;

  if (class->state == OSBF_CLOSED)
    osbf_raise(h, "Cannot dump a closed class");

  if (verbose == 1) {
    buckets = class->buckets;
    for (i = 0; i <= class->header->num_buckets; i++) {
      if ((count = buckets[i].count) != 0) {
        uint32_t distance, right_position;
        uint32_t real_position, rp;

        used_buckets++;
        chain_len++;
        if (count > max_count)
          max_count = count;

        /* calculate max displacement */
        right_position = buckets[i].hash1 % class->header->num_buckets;
	real_position = i;
	if (right_position <= real_position)
	  distance = real_position - right_position;
	else
	  distance = class->header->num_buckets + real_position -
	    right_position;
	if (distance > max_displacement)
	  max_displacement = distance;

	/* check if the bucket is unreachable */
	for (rp = right_position; rp != real_position; rp++)
	  {
	    if (rp >= class->header->num_buckets)
	      {
	        rp = 0;
	        if (rp == real_position)
	          break;
	      }
	    if (buckets[rp].count == 0)
	      break;
	  }
	if (rp != real_position)
	  {
	    unreachable++;
	  }
	
	if (chain_len > 0)
	  {
	    if (chain_len > max_chain)
	      max_chain = chain_len;
	    chain_len_sum += chain_len;
	    num_chains++;
	    chain_len = 0;
	    /* check if the first chain starts */
	    /* at the the first bucket */
	    if (i == 0 && num_chains == 1 && buckets[0].count != 0)
	      first_chain_len = chain_len;
          }

      }
    }
    
    /* check if last and first chains are the same */
    /* not sure this makes sense any longer XXX */
    if (chain_len > 0)
      {
        if (first_chain_len == 0)
          num_chains++;
        else
          chain_len += first_chain_len;
        chain_len_sum += chain_len;
        if (chain_len > max_chain)
          max_chain = chain_len;
      }
  }

  stats->db_id = class->header->db_id;
  stats->db_version = class->header->db_version;
  stats->db_flags = class->header->db_flags;
  stats->total_buckets = class->header->num_buckets;
  stats->bucket_size = sizeof(*class->buckets);
  stats->header_size = sizeof(class->header);
  stats->learnings = class->header->learnings;
  stats->extra_learnings = class->header->extra_learnings;
  stats->false_negatives = class->header->false_negatives;
  stats->false_positives = class->header->false_positives;
  stats->classifications = class->header->classifications;
  if (verbose == 1)
    {
      stats->used_buckets = used_buckets;
      stats->num_chains = num_chains;
      stats->max_chain = max_chain;
      if (num_chains > 0)
        stats->avg_chain = (double) chain_len_sum / num_chains;
      else
        stats->avg_chain = 0;
      stats->max_displacement = max_displacement;
      stats->unreachable = unreachable;
    }
}


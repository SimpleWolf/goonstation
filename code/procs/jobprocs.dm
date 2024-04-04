var/global/totally_random_jobs = FALSE

/proc/SetupOccupationsList()
	set background = 1

	var/list/new_occupations = list()

	for(var/occupation in occupations)
		if (!(new_occupations.Find(occupation)))
			new_occupations[occupation] = 1
		else
			new_occupations[occupation] += 1
	occupations = new_occupations
	return

/proc/FindOccupationCandidates(list/unassigned, job, level, set_antag_fallthrough = FALSE)
	set background = 1

	var/list/candidates = list()

	var/datum/job/J = find_job_in_controller_by_string(job)
	if(!J)
		CRASH("FindOccupationCandidates called with invalid job name: [job] at level: [level]")
	for (var/mob/new_player/player in unassigned)
		if(!player.client || !player.client.preferences) //Well shit.
			continue
		var/datum/preferences/P  = player.client.preferences
		if(player.mind?.is_antagonist())
			if (ticker?.mode && istype(ticker.mode, /datum/game_mode/revolution))
				if (J.cant_spawn_as_rev || ("loyalist" in P.traitPreferences.traits_selected)) //Why would an NT Loyalist be a revolutionary?
					continue
			else if((ticker?.mode && istype(ticker.mode, /datum/game_mode/gang)) && (job != "Staff Assistant"))
				continue
			else if ((ticker?.mode && istype(ticker.mode, /datum/game_mode/conspiracy)) && J.cant_spawn_as_con)
				continue

		if (jobban_isbanned(player, job))
			continue
		if (!J.allow_traitors && player.mind.special_role || !J.allow_spy_theft && player.mind.special_role == ROLE_SPY_THIEF)
			if(set_antag_fallthrough)
				player.antag_fallthrough = TRUE
			continue
		if (!J.allow_antag_fallthrough && player.antag_fallthrough)
			continue

		if (global.totally_random_jobs)
			candidates += player
			continue

		if (J.needs_college && !player.has_medal("Unlike the director, I went to college"))
			continue
		if (J.requires_whitelist && !NT.Find(ckey(player.mind.key)))
			continue
		if (P.jobs_unwanted.Find(J.name))
			continue
		if (level == 1 && P.job_favorite == J.name)
			candidates += player
		else if (level == 2 && P.jobs_med_priority.Find(J.name))
			candidates += player
		else if (level == 3 && P.jobs_low_priority.Find(J.name))
			candidates += player

	return candidates

/proc/DivideOccupations()
	set background = 1

	var/list/unassigned = list()

	for (var/client/C)
		var/mob/new_player/player = C.mob
		if (!istype(player) || !player.mind) continue
		if ((player.mind.special_role == ROLE_WRAITH) || (player.mind.special_role == ROLE_BLOB) || (player.mind.special_role == ROLE_FLOCKMIND))
			continue //If they aren't spawning in as crew they shouldn't take a job slot.
		if (player.ready && !player.mind.assigned_role)
			unassigned += player

	var/percent_readied_up = length(clients) ? (length(unassigned)/length(clients)) * 100 : 0
	logTheThing(LOG_DEBUG, null, "<b>Aloe</b>: roughly [percent_readied_up]% of players were readied up at roundstart (blobs and wraiths don't count).")

	if (!length(unassigned))
		return 0

	// If the mode is construction, ignore all this shit and sort everyone into the construction worker job.
	if (master_mode == "construction")
		for (var/mob/new_player/player in unassigned)
			player.mind.assigned_role = "Construction Worker"
		return

	var/list/pick1 = list()
	var/list/pick2 = list()
	var/list/pick3 = list()

	// Stick all the available jobs into its own list so we can wiggle the fuck outta it
	var/list/available_job_roles = list()
	// Apart from ones in THIS list, which are jobs we want to assign before any others
	var/list/high_priority_jobs = list()
	// This list is for jobs like staff assistant which have no limits, or other special-case
	// shit to hand out to people who didn't get one of the main limited slot jobs
	var/list/low_priority_jobs = list()

	var/list/medical_staff = list()
	var/list/engineering_staff = list()
	var/list/research_staff = list()
	var/list/security_officers = list()


	for(var/datum/job/JOB in job_controls.staple_jobs)
		if (JOB.variable_limit)
			JOB.recalculate_limit(length(unassigned))
		// If it's hi-pri, add it to that list. Simple enough
		if (JOB.high_priority_job)
			high_priority_jobs.Add(JOB)
		// If we've got a job with the low priority var set or no limit, chuck it in the
		// low-pri list and move onto the next job - if we don't do this, the first time
		// it hits a limitless job it'll get stuck on it and hand it out to everyone then
		// boot the game up resulting in ~WEIRD SHIT~
		else if (JOB.low_priority_job)
			low_priority_jobs += JOB.name
			continue
		// otherwise it's a normal role so it goes in that list instead
		else
			available_job_roles.Add(JOB)

	// Wiggle it like a pissy caterpillar
	shuffle_list(available_job_roles)
	// Wiggle the players too so that priority isn't determined by key alphabetization
	shuffle_list(unassigned)

	// First we deal with high-priority jobs like Captain or AI which generally will always
	// be present on the station - we want these assigned first just to be sure
	// Though we don't want to do this in sandbox mode where it won't matter anyway
	if(master_mode != "sandbox")
		for(var/datum/job/JOB in high_priority_jobs)
			if (!length(unassigned)) break

			if (JOB.limit > 0 && JOB.assigned >= JOB.limit) continue

			// get all possible candidates for it
			pick1 = FindOccupationCandidates(unassigned,JOB.name,1)
			pick2 = FindOccupationCandidates(unassigned,JOB.name,2)
			pick3 = FindOccupationCandidates(unassigned,JOB.name,3)

			// now assign them - i'm not hardcoding limits on these because i don't think any
			// of us are quite stupid enough to edit the AI's limit to -1 preround and have a
			// horrible multicore PC station round.. (i HOPE anyway)
			for(var/mob/new_player/candidate in pick1)
				if(!candidate.client) continue
				if (JOB.assigned >= JOB.limit || !length(unassigned)) break
				logTheThing(LOG_DEBUG, null, "<b>I Said No/Jobs:</b> [candidate] took [JOB.name] from High Priority Job Picker Lv1")
				candidate.mind.assigned_role = JOB.name
				logTheThing(LOG_DEBUG, candidate, "assigned job: [candidate.mind.assigned_role]")
				unassigned -= candidate
				JOB.assigned++
			for(var/mob/new_player/candidate in pick2)
				if(!candidate.client) continue
				if (JOB.assigned >= JOB.limit || !length(unassigned)) break
				logTheThing(LOG_DEBUG, null, "<b>I Said No/Jobs:</b> [candidate] took [JOB.name] from High Priority Job Picker Lv2")
				candidate.mind.assigned_role = JOB.name
				logTheThing(LOG_DEBUG, candidate, "assigned job: [candidate.mind.assigned_role]")
				unassigned -= candidate
				JOB.assigned++
			for(var/mob/new_player/candidate in pick3)
				if(!candidate.client) continue
				if (JOB.assigned >= JOB.limit || !length(unassigned)) break
				logTheThing(LOG_DEBUG, null, "<b>I Said No/Jobs:</b> [candidate] took [JOB.name] from High Priority Job Picker Lv3")
				candidate.mind.assigned_role = JOB.name
				logTheThing(LOG_DEBUG, candidate, "assigned job: [candidate.mind.assigned_role]")
				unassigned -= candidate
				JOB.assigned++
	else
		// if we are in sandbox mode just roll the hi-pri jobs back into the regular list so
		// people can still get them if they chose them
		available_job_roles = available_job_roles | high_priority_jobs

	// Next we go through each player and see if we can get them into their favorite jobs
	// If we don't do this loop then the main loop below might get to a job they have in their
	// medium or low priority lists first and give them that one rather than their favorite
	for (var/mob/new_player/player in unassigned)
		// If they don't have a favorite, skip em
		if (derelict_mode) // stop freaking out at the weird jobs
			continue
		if (global.totally_random_jobs) //  we don't care about favorites
			continue
		if (!player?.client?.preferences || player?.client?.preferences.job_favorite == null)
			continue
		// Now get the in-system job via the string
		var/datum/job/JOB = find_job_in_controller_by_string(player.client.preferences.job_favorite)
		// Do a few checks to make sure they're allowed to have this job
		if (ticker?.mode && istype(ticker.mode, /datum/game_mode/revolution))
			if(player.mind?.is_antagonist() && (JOB.cant_spawn_as_rev || JOB.cant_spawn_as_con))
				// Fixed AI, security etc spawning as rev heads. The special job picker doesn't care about that var yet,
				// but I'm not gonna waste too much time tending to a basically abandoned game mode (Convair880).
				continue
		if (!JOB || jobban_isbanned(player,JOB.name))
			continue
		if (JOB.needs_college && !player.has_medal("Unlike the director, I went to college"))
			continue
		if (JOB.requires_whitelist && !NT.Find(ckey(player.mind.key)))
			continue
		if (!JOB.allow_traitors && player.mind.special_role ||  !JOB.allow_spy_theft && player.mind.special_role == ROLE_SPY_THIEF)
			player.antag_fallthrough = TRUE
			continue
		// If there's an open job slot for it, give the player the job and remove them from
		// the list of unassigned players, hey presto everyone's happy (except clarks probly)
		if (JOB.limit < 0 || !(JOB.assigned >= JOB.limit))
			if (istype(JOB, /datum/job/engineering/engineer))
				engineering_staff += player
			else if (istype(JOB, /datum/job/research/scientist))
				research_staff += player
			else if (istype(JOB, /datum/job/research/medical_doctor))
				medical_staff += player
			else if (istype(JOB, /datum/job/security/security_officer))
				security_officers += player

			logTheThing(LOG_DEBUG, null, "<b>I Said No/Jobs:</b> [player] took [JOB.name] from favorite selector")
			player.mind.assigned_role = JOB.name
			logTheThing(LOG_DEBUG, player, "assigned job: [player.mind.assigned_role]")
			unassigned -= player
			JOB.assigned++

	// Do this loop twice - once for med priority and once for low priority, because elsewise
	// it was causing weird shit to happen where having something in low priority would
	// sometimes cause you to get that instead of a higher prioritized job
	for(var/datum/job/JOB in available_job_roles)
		// If we've got everyone a job, then stop wasting cycles and get on with the show
		if (!length(unassigned)) break
		// If there's no more slots for this job available, move onto the next one
		if (JOB.limit > 0 && JOB.assigned >= JOB.limit) continue
		// First, rebuild the lists of who wants to be this job
		pick2 = FindOccupationCandidates(unassigned,JOB.name,2, TRUE)
		// Now loop through the candidates in order of priority, and elect them to the
		// job position if possible - if at any point the job is filled, break the loops
		for(var/mob/new_player/candidate in pick2)
			if (JOB.assigned >= JOB.limit || !length(unassigned))
				break

			if (istype(JOB, /datum/job/engineering/engineer))
				engineering_staff += candidate
			else if (istype(JOB, /datum/job/research/scientist))
				research_staff += candidate
			else if (istype(JOB, /datum/job/research/medical_doctor))
				medical_staff += candidate
			else if (istype(JOB, /datum/job/security/security_officer))
				security_officers += candidate

			logTheThing(LOG_DEBUG, null, "<b>I Said No/Jobs:</b> [candidate] took [JOB.name] from Level 2 Job Picker")
			candidate.mind.assigned_role = JOB.name
			logTheThing(LOG_DEBUG, candidate, "assigned job: [candidate.mind.assigned_role]")
			unassigned -= candidate
			JOB.assigned++

	// And then again for low priority
	for(var/datum/job/JOB in available_job_roles)
		if (!length(unassigned))
			break

		if (JOB.limit == 0)
			continue

		if (JOB.limit > 0 && JOB.assigned >= JOB.limit)
			continue

		pick3 = FindOccupationCandidates(unassigned,JOB.name,3, TRUE)
		for(var/mob/new_player/candidate in pick3)
			if (JOB.assigned >= JOB.limit || !length(unassigned))
				break

			if (istype(JOB, /datum/job/engineering/engineer))
				engineering_staff += candidate
			else if (istype(JOB, /datum/job/research/scientist))
				research_staff += candidate
			else if (istype(JOB, /datum/job/research/medical_doctor))
				medical_staff += candidate
			else if (istype(JOB, /datum/job/security/security_officer))
				security_officers += candidate

			logTheThing(LOG_DEBUG, null, "<b>I Said No/Jobs:</b> [candidate] took [JOB.name] from Level 3 Job Picker")
			candidate.mind.assigned_role = JOB.name
			logTheThing(LOG_DEBUG, candidate, "assigned job: [candidate.mind.assigned_role]")
			unassigned -= candidate
			JOB.assigned++

	/////////////////////////////////////////////////
	///////////COMMAND PROMOTIONS////////////////////
	/////////////////////////////////////////////////

	//Find the command jobs, if they are unfilled, pick a random person from within that department to be that command officer
	//if they had the command job in their medium or low priority jobs
	for(var/datum/job/JOB in available_job_roles)
		//cheaper to discout this first than type check here *I think*
		if (istype(JOB, /datum/job/command) && JOB.limit > 0 && JOB.assigned < JOB.limit)
			var/list/picks
			if (istype(JOB, /datum/job/command/chief_engineer))
				picks = FindPromotionCandidates(engineering_staff, JOB)
			else if (istype(JOB, /datum/job/command/research_director))
				picks = FindPromotionCandidates(research_staff, JOB)
			else if (istype(JOB, /datum/job/command/medical_director))
				picks = FindPromotionCandidates(medical_staff, JOB)
			else if (istype(JOB, /datum/job/command/head_of_security))
				picks = FindPromotionCandidates(security_officers, JOB)
			if (!length(picks))
				continue
			var/mob/new_player/candidate = pick(picks)
			logTheThing(LOG_DEBUG, null, "<b>kyle:</b> [candidate] took [JOB.name] from Job Promotion Picker")
			candidate.mind.assigned_role = JOB.name
			logTheThing(LOG_DEBUG, candidate, "reassigned job: [candidate.mind.assigned_role]")
			JOB.assigned++


	// If there's anyone left without a job after this, lump them with a randomly
	// picked low priority role and be done with it
	if (!length(low_priority_jobs))
		// we really need to fix this or it'll be some kinda weird inf loop shit
		low_priority_jobs += "Staff Assistant"
	for (var/mob/new_player/player in unassigned)
		if(!player?.mind) continue
		logTheThing(LOG_DEBUG, null, "<b>I Said No/Jobs:</b> [player] given a low priority role")
		player.mind.assigned_role = pick(low_priority_jobs)
		logTheThing(LOG_DEBUG, player, "assigned job: [player.mind.assigned_role]")

	return 1

//Given a list of candidates returns candidates that are acceptable to be promoted based on their medium/low priorities
//ideally JOB should only be a command position. eg. CE, RD, MD
/proc/FindPromotionCandidates(list/staff, var/datum/job/JOB)
	var/list/picks = FindOccupationCandidates(staff,JOB.name,2)

	//If there are no acceptable candidates (no inappropriate antags, no job bans) who have it in their medium priority list
	if (!length(picks))
		picks = FindOccupationCandidates(staff,JOB.name,3)
	return picks

/proc/equip_job_items(var/datum/job/JOB, var/mob/living/carbon/human/H)
	// Jumpsuit - Important! Must be equipped early to provide valid slots for other items
	if (JOB.slot_jump && length(JOB.slot_jump) > 1)
		H.equip_new_if_possible(weighted_pick(JOB.slot_jump), SLOT_W_UNIFORM)
	else if (length(JOB.slot_jump))
		H.equip_new_if_possible(JOB.slot_jump[1], SLOT_W_UNIFORM)
	// Backpack and contents
	if (JOB.slot_back && length(JOB.slot_back) > 1)
		H.equip_new_if_possible(weighted_pick(JOB.slot_back), SLOT_BACK)
	else if (length(JOB.slot_back))
		H.equip_new_if_possible(JOB.slot_back[1], SLOT_BACK)
	if (JOB.slot_back && length(JOB.items_in_backpack))
		for (var/X in JOB.items_in_backpack)
			if(ispath(X))
				H.equip_new_if_possible(X, SLOT_IN_BACKPACK)
	// Belt and contents
	if (JOB.slot_belt && length(JOB.slot_belt) > 1)
		H.equip_new_if_possible(weighted_pick(JOB.slot_belt), SLOT_BELT)
	else if (length(JOB.slot_belt))
		H.equip_new_if_possible(JOB.slot_belt[1], SLOT_BELT)
	if (JOB.slot_belt && length(JOB.items_in_belt) && H.belt?.storage)
		for (var/X in JOB.items_in_belt)
			if(ispath(X))
				H.equip_new_if_possible(X, SLOT_IN_BELT)
	// Footwear
	if (JOB.slot_foot && length(JOB.slot_foot) > 1)
		H.equip_new_if_possible(weighted_pick(JOB.slot_foot), SLOT_SHOES)
	else if (length(JOB.slot_foot))
		H.equip_new_if_possible(JOB.slot_foot[1], SLOT_SHOES)
	// Suit
	if (JOB.slot_suit && length(JOB.slot_suit) > 1)
		H.equip_new_if_possible(weighted_pick(JOB.slot_suit), SLOT_WEAR_SUIT)
	else if (length(JOB.slot_suit))
		H.equip_new_if_possible(JOB.slot_suit[1], SLOT_WEAR_SUIT)
	// Ears
	if (JOB.slot_ears && length(JOB.slot_ears) > 1)
		H.equip_new_if_possible(weighted_pick(JOB.slot_ears), SLOT_EARS)
	else if (length(JOB.slot_ears))
		if (!(H.traitHolder && H.traitHolder.hasTrait("allears") && ispath(JOB.slot_ears[1],
	/obj/item/device/radio/headset)))
			H.equip_new_if_possible(JOB.slot_ears[1], SLOT_EARS)
	// Mask
	if (JOB.slot_mask && length(JOB.slot_mask) > 1)
		H.equip_new_if_possible(weighted_pick(JOB.slot_mask), SLOT_WEAR_MASK)
	else if (length(JOB.slot_mask))
		H.equip_new_if_possible(JOB.slot_mask[1], SLOT_WEAR_MASK)
	// Gloves
	if (JOB.slot_glov && length(JOB.slot_glov) > 1)
		H.equip_new_if_possible(weighted_pick(JOB.slot_glov), SLOT_GLOVES)
	else if (length(JOB.slot_glov))
		H.equip_new_if_possible(JOB.slot_glov[1], SLOT_GLOVES)
	// Eyes
	if (JOB.slot_eyes && length(JOB.slot_eyes) > 1)
		H.equip_new_if_possible(weighted_pick(JOB.slot_eyes), SLOT_GLASSES)
	else if (length(JOB.slot_eyes))
		H.equip_new_if_possible(JOB.slot_eyes[1], SLOT_GLASSES)
	// Head
	if (JOB.slot_head && length(JOB.slot_head) > 1)
		H.equip_new_if_possible(weighted_pick(JOB.slot_head), SLOT_HEAD)
	else if (length(JOB.slot_head))
		H.equip_new_if_possible(JOB.slot_head[1], SLOT_HEAD)
	// Left pocket
	if (JOB.slot_poc1 && length(JOB.slot_poc1) > 1)
		H.equip_new_if_possible(weighted_pick(JOB.slot_poc1), SLOT_L_STORE)
	else if (length(JOB.slot_poc1))
		H.equip_new_if_possible(JOB.slot_poc1[1], SLOT_L_STORE)
	// Right pocket
	if (JOB.slot_poc2 && length(JOB.slot_poc2) > 1)
		H.equip_new_if_possible(weighted_pick(JOB.slot_poc2), SLOT_R_STORE)
	else if (length(JOB.slot_poc2))
		H.equip_new_if_possible(JOB.slot_poc2[1], SLOT_R_STORE)
	// Left hand
	if (JOB.slot_lhan && length(JOB.slot_lhan) > 1)
		H.equip_new_if_possible(weighted_pick(JOB.slot_poc1), SLOT_L_HAND)
	else if (length(JOB.slot_lhan))
		H.equip_new_if_possible(JOB.slot_lhan[1], SLOT_L_HAND)
	// Right hand
	if (JOB.slot_rhan && length(JOB.slot_rhan) > 1)
		H.equip_new_if_possible(weighted_pick(JOB.slot_poc1), SLOT_R_HAND)
	else if (length(JOB.slot_rhan))
		H.equip_new_if_possible(JOB.slot_rhan[1], SLOT_R_HAND)

	//#ifdef APRIL_FOOLS
	//H.back?.setMaterial(getMaterial("jean"))
	//H.gloves?.setMaterial(getMaterial("jean"))
	//H.wear_suit?.setMaterial(getMaterial("jean"))
	//H.wear_mask?.setMaterial(getMaterial("jean"))
	//H.w_uniform?.setMaterial(getMaterial("jean"))
	//H.shoes?.setMaterial(getMaterial("jean"))
	//H.head?.setMaterial(getMaterial("jean"))
	//#endif

//hey i changed this from a /human/proc to a /living/proc so that critters (from the job creator) would latejoin properly	-- MBC
/mob/living/proc/Equip_Rank(rank, joined_late, no_special_spawn)
	var/datum/job/JOB = find_job_in_controller_by_string(rank)
	if (!JOB)
		boutput(src, SPAN_ALERT("<b>Something went wrong setting up your rank and equipment! Report this to a coder.</b>"))
		return

	if (JOB.announce_on_join)
		SPAWN(1 SECOND)
			boutput(world, "<b>[src.name] is the [JOB.name]!</b>")
	boutput(src, "<B>You are the [JOB.name].</B>")
	src.job = JOB.name
	src.mind.assigned_role = JOB.name

	if (!joined_late)
		if (ticker?.mode && !istype(ticker.mode, /datum/game_mode/construction))
			if (job_start_locations && islist(job_start_locations[JOB.name]))
				var/tries = 8
				var/turf/T
				do
					T = pick(job_start_locations[JOB.name])
				while((locate(/mob) in T) && tries--)
				src.set_loc(T)
		else
			src.set_loc(pick_landmark(LANDMARK_LATEJOIN))
	else
		src.unlock_medal("Fish", 1)

	if (time2text(world.realtime + 0.5 DAYS, "MM DD") == "12 25" || time2text(world.realtime - 0.5 DAYS, "MM DD") == "12 25")
		src.unlock_medal("A Holly Jolly Spacemas")

	if (ishuman(src))
		var/mob/living/carbon/human/H = src

		//remove problem traits from people on pod_wars
		if (istype(ticker.mode, /datum/game_mode/pod_wars))
			H.traitHolder.removeTrait("stowaway")
			H.traitHolder.removeTrait("pilot")
			H.traitHolder.removeTrait("sleepy")
			H.traitHolder.removeTrait("puritan")

		H.Equip_Job_Slots(JOB)

	var/possible_new_mob = JOB.special_setup(src, no_special_spawn) //If special_setup creates a new mob for us, it should return the new mob!

	if (possible_new_mob && possible_new_mob != src)
		// ok so all the below shit checks if you're a human.
		// that's well and good but we need to be operating on possible_new_mob now,
		// because that's what the player is, not the one we were initially given.

		src = possible_new_mob // let's hope this breaks nothing


	if (ishuman(src) && JOB.add_to_manifest && !src.traitHolder.hasTrait("stowaway"))
		// Manifest stuff
		var/sec_note = ""
		var/med_note = ""
		var/synd_int_note = ""
		if(src.client?.preferences && !src.client.preferences.be_random_name)
			sec_note = src.client.preferences.security_note
			med_note = src.client.preferences.medical_note
			synd_int_note = src.client.preferences.synd_int_note
		var/obj/item/device/pda2/pda = locate() in src
		data_core.addManifest(src, sec_note, med_note, pda?.net_id, synd_int_note)

	if (ishuman(src))
		var/mob/living/carbon/human/H = src
		if (src.traitHolder && !src.traitHolder.hasTrait("stowaway"))
			H.spawnId(JOB)
		if (src.traitHolder && src.traitHolder.hasTrait("stowaway"))
			//Has the stowaway trait - they're hiding in a random locker
			var/list/obj/storage/SL = get_random_station_storage_list(closed=TRUE, breathable=TRUE)

			if(length(SL) > 0)
				src.set_loc(pick(SL))
				logTheThing(LOG_STATION, src, "has the Stowaway trait and spawns in storage at [log_loc(src)]")

		if (src.traitHolder && src.traitHolder.hasTrait("pilot"))		//Has the Pilot trait - they're drifting off-station in a pod. Note that environmental checks are not needed here.
			SPAWN(0) //pod creation sleeps for... reasons
				#define MAX_ALLOWED_ITERATIONS 300
				var/turf/pilotSpawnLocation = null

				var/valid_z_levels
				#ifdef UNDERWATER_MAP
				valid_z_levels = list(Z_LEVEL_MINING)
				#else
				valid_z_levels = list(Z_LEVEL_MINING, Z_LEVEL_DEBRIS)
				#endif

				// Counter to prevent infinite looping, in case space has been fully replaced
				var/safety = 0
				while(!istype(pilotSpawnLocation, /turf/space) && safety < MAX_ALLOWED_ITERATIONS)		//Trying to find a valid spawn location.
					pilotSpawnLocation = locate(rand(1, world.maxx), rand(1, world.maxy), pick(valid_z_levels))
					safety++
				// If it isn't a space turf just skip this all, we didn't find one
				if (istype(pilotSpawnLocation, /turf/space))								//Sanity check.
					src.set_loc(pilotSpawnLocation)
					var/obj/machinery/vehicle/V
					if (istype(pilotSpawnLocation, /turf/space/fluid))
						V = new/obj/machinery/vehicle/tank/minisub/pilot(pilotSpawnLocation)
					else											//This part of the code executes only if the map is a space one.
						V = new/obj/machinery/vehicle/miniputt/pilot(pilotSpawnLocation)
					if (V)
						for(var/obj/critter/gunbot/drone/snappedDrone in V.loc)	//Spawning onto a drone doesn't sound fun so the spawn location gets cleaned up.
							qdel(snappedDrone)
						V.finish_board_pod(src)
						V.life_support?.activate()

				#undef MAX_ALLOWED_ITERATIONS

		if (src.traitHolder && src.traitHolder.hasTrait("sleepy"))
			var/list/valid_beds = list()
			for_by_tcl(bed, /obj/stool/bed)
				if (bed.z == Z_LEVEL_STATION && istype(get_area(bed), /area/station)) //believe it or not there are station areas on nonstation z levels
					if (!locate(/mob/living/carbon/human) in get_turf(bed)) //this is slow but it's Probably worth it
						valid_beds += bed

			if (length(valid_beds) > 0)
				var/obj/stool/bed/picked = pick(valid_beds)
				src.set_loc(get_turf(picked))
				logTheThing(LOG_STATION, src, "has the Heavy Sleeper trait and spawns in a bed at [log_loc(picked)]")
				src.l_hand?.AddComponent(/datum/component/glued, src, 10 SECONDS, 5 SECONDS)
				src.r_hand?.AddComponent(/datum/component/glued, src, 10 SECONDS, 5 SECONDS)

				src.setStatus("resting", INFINITE_STATUS)
				src.setStatus("paralysis", 10 SECONDS)
				src.force_laydown_standup()

		// This should be here (overriding most other things), probably? - #11215
		// Vampires spawning in the chapel is bad. :(
		if (istype(src.loc.loc, /area/station/chapel) && (src.mind.special_role == ROLE_VAMPIRE))
			src.set_loc(pick_landmark(LANDMARK_LATEJOIN))

		if (prob(10) && islist(random_pod_codes) && length(random_pod_codes))
			var/obj/machinery/vehicle/V = pick(random_pod_codes)
			random_pod_codes -= V
			if (V?.lock?.code)
				boutput(src, SPAN_NOTICE("The unlock code to your pod ([V]) is: [V.lock.code]"))
				if (src.mind)
					src.mind.store_memory("The unlock code to your pod ([V]) is: [V.lock.code]")

		var/mob/current_mob = src // this proc does the sin of overwriting src, but it turns out that SPAWN doesn't care and uses the OG src, hence this
		SPAWN(0)
			if(!QDELETED(current_mob))
				current_mob.set_clothing_icon_dirty()
			sleep(0.1 SECONDS)
			if(!QDELETED(current_mob))
				current_mob.update_icons_if_needed()

		if (joined_late == 1 && map_settings && map_settings.arrivals_type != MAP_SPAWN_CRYO && JOB.radio_announcement)
			if (src.mind && src.mind.assigned_role) //ZeWaka: I'm adding this back here because hell if I know where it goes.
				for (var/obj/machinery/computer/announcement/A as anything in machine_registry[MACHINES_ANNOUNCEMENTS])
					if (!A.status && A.announces_arrivals)
						if (src.mind.assigned_role == "MODE") //ZeWaka: Fix for alien invasion dudes. Possibly not needed now.
							return
						else
							A.announce_arrival(src)

		//Equip_Bank_Purchase AFTER special_setup() call, because they might no longer be a human after that
	//this was previously indented in the ishuman() block, but I don't think it needs to be - Amylizzle
	if (possible_new_mob)
		var/mob/living/newmob = possible_new_mob
		newmob.Equip_Bank_Purchase(newmob.mind.purchased_bank_item)
	else
		src.Equip_Bank_Purchase(src.mind?.purchased_bank_item)

	return

/// Equip items from sensory traits
/mob/living/carbon/human/proc/equip_sensory_items()
	if (src.traitHolder.hasTrait("blind"))
		src.stow_in_available(src.glasses)
		src.equip_if_possible(new /obj/item/clothing/glasses/visor(src), SLOT_GLASSES)
	if (src.traitHolder.hasTrait("shortsighted"))
		src.stow_in_available(src.glasses)
		src.equip_if_possible(new /obj/item/clothing/glasses/regular(src), SLOT_GLASSES)
	if (src.traitHolder.hasTrait("deaf"))
		src.stow_in_available(src.ears)
		src.equip_if_possible(new /obj/item/device/radio/headset/deaf(src), SLOT_EARS)

/mob/living/carbon/human/proc/Equip_Job_Slots(var/datum/job/JOB)
	equip_job_items(JOB, src)
	if (JOB.slot_back)
		if (src.back?.storage)
			if(JOB.receives_disk)
				var/obj/item/disk/data/floppy/read_only/D = new /obj/item/disk/data/floppy/read_only(src)
				src.equip_if_possible(D, SLOT_IN_BACKPACK)
				var/datum/computer/file/clone/R = new
				R.fields["ckey"] = ckey(src.key)
				R.fields["name"] = src.real_name
				R.fields["id"] = copytext("\ref[src.mind]", 4, 12)

				var/datum/bioHolder/B = new/datum/bioHolder(null)
				B.CopyOther(src.bioHolder)

				R.fields["holder"] = B

				R.fields["abilities"] = null
				if (src.abilityHolder)
					var/datum/abilityHolder/A = src.abilityHolder.deepCopy()
					R.fields["abilities"] = A

				R.fields["defects"] = src.cloner_defects.copy()

				SPAWN(0)
					if(!isnull(src.traitHolder))
						R.fields["traits"] = src.traitHolder.copy()

				R.fields["imp"] = null
				R.fields["mind"] = src.mind
				D.root.add_file(R)

				if (JOB.receives_security_disk)
					var/datum/computer/file/record/authrec = new /datum/computer/file/record {name = "SECAUTH";} (src)
					authrec.fields = list("SEC"="[netpass_security]")
					D.root.add_file( authrec )
					D.read_only = 1

				D.name = "data disk - '[src.real_name]'"

			if(JOB.receives_badge)
				var/obj/item/clothing/suit/security_badge/B = new /obj/item/clothing/suit/security_badge(src)
				src.equip_if_possible(B, SLOT_IN_BACKPACK)
				B.badge_owner_name = src.real_name
				B.badge_owner_job = src.job

	if (src.traitHolder && src.traitHolder.hasTrait("pilot"))
		var/obj/item/tank/mini_oxygen/E = new /obj/item/tank/mini_oxygen(src.loc)
		src.force_equip(E, SLOT_IN_BACKPACK, TRUE)
		#ifdef UNDERWATER_MAP
		var/obj/item/clothing/suit/space/diving/civilian/SSW = new /obj/item/clothing/suit/space/diving/civilian(src.loc)
		src.force_equip(SSW, SLOT_IN_BACKPACK, TRUE)
		var/obj/item/clothing/head/helmet/space/engineer/diving/civilian/SHW = new /obj/item/clothing/head/helmet/space/engineer/diving/civilian(src.loc)
		src.force_equip(SHW, SLOT_IN_BACKPACK, TRUE)
		#else
		var/obj/item/clothing/suit/space/emerg/SSS = new /obj/item/clothing/suit/space/emerg(src.loc)
		src.force_equip(SSS, SLOT_IN_BACKPACK, TRUE)
		var/obj/item/clothing/head/emerg/SHS = new /obj/item/clothing/head/emerg(src.loc)
		src.force_equip(SHS, SLOT_IN_BACKPACK, TRUE)
		#endif
		src.equip_new_if_possible(/obj/item/clothing/mask/breath, SLOT_WEAR_MASK)
		var/obj/item/device/gps/GPSDEVICE = new /obj/item/device/gps(src.loc)
		src.force_equip(GPSDEVICE, SLOT_IN_BACKPACK, TRUE)

	if (src.traitHolder?.hasTrait("stowaway") || src.traitHolder?.hasTrait("pilot"))
		var/obj/item/device/pda2/pda = locate() in src
		src.u_equip(pda)
		qdel(pda)

	var/T = pick(trinket_safelist)
	var/obj/item/trinket = null

	if (src.traitHolder && src.traitHolder.hasTrait("pawnstar"))
		trinket = null //You better stay null, you hear me!
	else if (src.traitHolder && src.traitHolder.hasTrait("bald"))
		trinket = src.create_wig()
		src.bioHolder.mobAppearance.customization_first = new /datum/customization_style/none
		src.bioHolder.mobAppearance.customization_second = new /datum/customization_style/none
		src.bioHolder.mobAppearance.customization_third = new /datum/customization_style/none
		src.update_colorful_parts()
	else if (src.traitHolder && src.traitHolder.hasTrait("loyalist"))
		trinket = new/obj/item/clothing/head/NTberet(src)
	else if (src.traitHolder && src.traitHolder.hasTrait("petasusaphilic"))
		var/picked = pick(filtered_concrete_typesof(/obj/item/clothing/head, /proc/filter_trait_hats))
		trinket = new picked(src)
	else if (src.traitHolder && src.traitHolder.hasTrait("conspiracytheorist"))
		trinket = new/obj/item/clothing/head/tinfoil_hat
	else if (src.traitHolder && src.traitHolder.hasTrait("beestfriend"))
		if (prob(15))
			trinket = new/obj/item/reagent_containers/food/snacks/ingredient/egg/bee/buddy(src)
		else
			trinket = new/obj/item/reagent_containers/food/snacks/ingredient/egg/bee(src)
	else if (src.traitHolder && src.traitHolder.hasTrait("lunchbox"))
		var/random_lunchbox_path = pick(childrentypesof(/obj/item/storage/lunchbox))
		trinket = new random_lunchbox_path(src)
	else if (src.traitHolder && src.traitHolder.hasTrait("allergic"))
		trinket = new/obj/item/reagent_containers/emergency_injector/epinephrine(src)
	else
		trinket = new T(src)

	var/list/obj/item/trinkets_to_equip = list()

	if (trinket)
		src.trinket = get_weakref(trinket)
		trinket.name = "[src.real_name][pick_string("trinkets.txt", "modifiers")] [trinket.name]"
		trinket.quality = rand(5,80)
		trinkets_to_equip += trinket

	// fake trinket-like zippo lighter for the smoker trait
	if (src.traitHolder && src.traitHolder.hasTrait("smoker"))
		var/obj/item/device/light/zippo/smoker_zippo = new(src)
		smoker_zippo.name = "[src.real_name][pick_string("trinkets.txt", "modifiers")] [smoker_zippo.name]"
		smoker_zippo.quality = rand(5,80)
		trinkets_to_equip += smoker_zippo

	for (var/obj/item/I in trinkets_to_equip)
		var/equipped = 0
		if (src.back?.storage && src.equip_if_possible(I, SLOT_IN_BACKPACK))
			equipped = 1
		else if (src.belt?.storage && src.equip_if_possible(I, SLOT_IN_BELT))
			equipped = 1
		if (!equipped)
			if (!src.l_store && src.equip_if_possible(I, SLOT_L_STORE))
				equipped = 1
			else if (!src.r_store && src.equip_if_possible(I, SLOT_R_STORE))
				equipped = 1
			else if (!src.l_hand && src.equip_if_possible(I, SLOT_L_HAND))
				equipped = 1
			else if (!src.r_hand && src.equip_if_possible(I, SLOT_R_HAND))
				equipped = 1

			if (!equipped) // we've tried most available storage solutions here now so uh just put it on the ground
				I.set_loc(get_turf(src))

		if (src.traitHolder && src.traitHolder.hasTrait("nolegs"))
			if (src.limbs)
				SPAWN(6 SECONDS)
					if (src.limbs.l_leg)
						src.limbs.l_leg.delete()
					if (src.limbs.r_leg)
						src.limbs.r_leg.delete()
				new /obj/stool/chair/comfy/wheelchair(get_turf(src))

		// Special mutantrace items
		if (src.traitHolder && src.traitHolder.hasTrait("pug"))
			src.put_in_hand_or_drop(new /obj/item/reagent_containers/food/snacks/cookie/dog)
		else if (src.traitHolder && src.traitHolder.hasTrait("skeleton"))
			src.put_in_hand_or_drop(new /obj/item/joint_wax)

	src.equip_sensory_items()

/mob/living/carbon/human/proc/spawnId(var/datum/job/JOB)
#ifdef DEBUG_EVERYONE_GETS_CAPTAIN_ID
	JOB = new /datum/job/command/captain
#endif
	var/obj/item/card/id/C = null
	if (!JOB || !JOB.slot_card)
		return null

	C = new JOB.slot_card(src)

	if(C)
		var/realName = src.real_name

		if(src.traitHolder && src.traitHolder.hasTrait("clericalerror"))
			realName = replacetext(realName, "a", "o")
			realName = replacetext(realName, "e", "i")
			realName = replacetext(realName, "u", pick("a", "e"))
			if(prob(50)) realName = replacetext(realName, "n", "m")
			if(prob(50)) realName = replacetext(realName, "t", pick("d", "k"))
			if(prob(50)) realName = replacetext(realName, "p", pick("b", "t"))

			var/datum/db_record/B = FindBankAccountByName(src.real_name)
			if (B?["name"])
				B["name"] = realName

		C.registered = realName
		C.assignment = JOB.name
		C.name = "[C.registered]'s ID Card ([C.assignment])"
		C.access = JOB.access.Copy()
		C.pronouns = src.get_pronouns()

		if(!src.equip_if_possible(C, SLOT_WEAR_ID))
			src.equip_if_possible(C, SLOT_IN_BACKPACK)

		if(src.pin)
			C.pin = src.pin

	for (var/obj/item/device/pda2/PDA in src.contents)
		PDA.owner = src.real_name
		PDA.ownerAssignment = JOB.name
		PDA.name = "PDA-[src.real_name]"

		if(src.mind)
			src.mind.originalPDA = PDA

	boutput(src, SPAN_NOTICE("Your pin to your ID is: [C.pin]"))
	if (src.mind)
		src.mind.store_memory("Your pin to your ID is: [C.pin]")
	src.mind?.remembered_pin = C.pin

	if (wagesystem.jobs[JOB.name])
		var/cashModifier = 1
		if (src.traitHolder && src.traitHolder.hasTrait("pawnstar"))
			cashModifier = 1.25

		var/obj/item/currency/spacecash/S = new /obj/item/currency/spacecash
		S.setup(src,round(wagesystem.jobs[JOB.name] * cashModifier))

		if (isnull(src.get_slot(SLOT_R_STORE)))
			src.equip_if_possible(S, SLOT_R_STORE)
		else if (isnull(src.get_slot(SLOT_L_STORE)))
			src.equip_if_possible(S, SLOT_L_STORE)
		else
			src.equip_if_possible(S, SLOT_IN_BACKPACK)
	else
		var/shitstore = rand(1,3)
		switch(shitstore)
			if(1)
				src.equip_new_if_possible(/obj/item/pen, SLOT_R_STORE)
			if(2)
				src.equip_new_if_possible(/obj/item/reagent_containers/food/drinks/water, SLOT_R_STORE)


/mob/living/carbon/human/proc/JobEquipSpawned(rank, no_special_spawn)
	var/datum/job/JOB = find_job_in_controller_by_string(rank)
	if (!JOB)
		boutput(src, SPAN_ALERT("<b>UH OH, the game couldn't find your job to set it up! Report this to a coder.</b>"))
		return

	equip_job_items(JOB, src)

	if (ishuman(src) && JOB.spawn_id)
		src.spawnId(JOB)

	JOB.special_setup(src, no_special_spawn)

	update_clothing()
	update_inhands()

	return

//////////////////////////////////////////////
// cogwerks - personalized trinkets project //
/////////////////////////////////////////////

var/list/trinket_safelist = list(
	/obj/item/basketball,
	/obj/item/instrument/bikehorn,
	/obj/item/brick,
	/obj/item/clothing/glasses/eyepatch,
	/obj/item/clothing/glasses/regular,
	/obj/item/clothing/glasses/sunglasses/tanning,
	/obj/item/clothing/gloves/boxing,
	/obj/item/clothing/mask/horse_mask,
	/obj/item/clothing/mask/clown_hat,
	/obj/item/clothing/head/cowboy,
	/obj/item/clothing/shoes/cowboy,
	/obj/item/clothing/shoes/moon,
	/obj/item/clothing/suit/sweater,
	/obj/item/clothing/suit/sweater/red,
	/obj/item/clothing/suit/sweater/green,
	/obj/item/clothing/suit/sweater/grandma,
	/obj/item/clothing/under/shorts,
	/obj/item/clothing/under/suit/pinstripe,
	/obj/item/cigpacket,
	/obj/item/coin,
	/obj/item/crowbar,
	/obj/item/pen/crayon/lipstick,
	/obj/item/dice,
	/obj/item/dice/d20,
	/obj/item/device/light/flashlight,
	/obj/item/device/key/random,
	/obj/item/extinguisher,
	/obj/item/firework,
	/obj/item/football,
	/obj/item/stamped_bullion,
	/obj/item/instrument/harmonica,
	/obj/item/horseshoe,
	/obj/item/kitchen/utensil/knife,
	/obj/item/raw_material/rock,
	/obj/item/pen/fancy,
	/obj/item/pen/odd,
	/obj/item/plant/herb/cannabis/spawnable,
	/obj/item/razor_blade,
	/obj/item/rubberduck,
	/obj/item/instrument/saxophone,
	/obj/item/scissors,
	/obj/item/screwdriver,
	/obj/item/skull,
	/obj/item/stamp,
	/obj/item/instrument/vuvuzela,
	/obj/item/wrench,
	/obj/item/device/light/zippo,
	/obj/item/reagent_containers/food/drinks/bottle/beer,
	/obj/item/reagent_containers/food/drinks/bottle/vintage,
	/obj/item/reagent_containers/food/drinks/bottle/vodka,
	/obj/item/reagent_containers/food/drinks/bottle/rum,
	/obj/item/reagent_containers/food/drinks/bottle/hobo_wine/safe,
	/obj/item/reagent_containers/food/snacks/burger,
	/obj/item/reagent_containers/food/snacks/burger/cheeseburger,
	/obj/item/reagent_containers/food/snacks/burger/moldy,
	/obj/item/reagent_containers/food/snacks/candy/chocolate,
	/obj/item/reagent_containers/food/snacks/chips,
	/obj/item/reagent_containers/food/snacks/cookie,
	/obj/item/reagent_containers/food/snacks/ingredient/egg,
	/obj/item/reagent_containers/food/snacks/ingredient/egg/bee,
	/obj/item/reagent_containers/food/snacks/plant/apple,
	/obj/item/reagent_containers/food/snacks/plant/banana,
	/obj/item/reagent_containers/food/snacks/plant/potato,
	/obj/item/reagent_containers/food/snacks/sandwich/pb,
	/obj/item/reagent_containers/food/snacks/sandwich/cheese,
	/obj/item/reagent_containers/syringe/krokodil,
	/obj/item/reagent_containers/syringe/morphine,
	/obj/item/reagent_containers/patch/LSD,
	/obj/item/reagent_containers/patch/lsd_bee,
	/obj/item/reagent_containers/patch/nicotine,
	/obj/item/reagent_containers/glass/bucket,
	/obj/item/reagent_containers/glass/beaker,
	/obj/item/reagent_containers/food/drinks/drinkingglass,
	/obj/item/reagent_containers/food/drinks/drinkingglass/shot,
	/obj/item/storage/pill_bottle/bathsalts,
	/obj/item/storage/pill_bottle/catdrugs,
	/obj/item/storage/pill_bottle/crank,
	/obj/item/storage/pill_bottle/cyberpunk,
	/obj/item/storage/pill_bottle/methamphetamine,
	/obj/item/spraybottle,
	/obj/item/staple_gun,
	/obj/item/clothing/head/NTberet,
	/obj/item/clothing/head/biker_cap,
	/obj/item/clothing/head/black,
	/obj/item/clothing/head/blue,
	/obj/item/clothing/head/chav,
	/obj/item/clothing/head/det_hat,
	/obj/item/clothing/head/green,
	/obj/item/clothing/head/helmet/hardhat,
	/obj/item/clothing/head/merchant_hat,
	/obj/item/clothing/head/mj_hat,
	/obj/item/clothing/head/red,
	/obj/item/clothing/head/that,
	/obj/item/clothing/head/wig,
	/obj/item/clothing/head/turban,
	/obj/item/dice/magic8ball,
	/obj/item/reagent_containers/food/drinks/mug/random_color,
	/obj/item/reagent_containers/food/drinks/skull_chalice,
	/obj/item/pen/marker/random,
	/obj/item/pen/crayon/random,
	/obj/item/clothing/gloves/yellow/unsulated,
	/obj/item/reagent_containers/food/snacks/fortune_cookie,
	/obj/item/instrument/triangle,
	/obj/item/instrument/tambourine,
	/obj/item/instrument/cowbell,
	/obj/item/toy/plush/small/bee,
	/obj/item/paper/book/from_file/the_trial,
	/obj/item/paper/book/from_file/deep_blue_sea,
	/obj/item/clothing/suit/bedsheet/cape/red,
	/obj/item/disk/data/cartridge/clown,
	/obj/item/clothing/mask/cigarette/cigar,
	/obj/item/device/light/sparkler,
	/obj/item/toy/sponge_capsule,
	/obj/item/reagent_containers/food/snacks/plant/pear,
	/obj/item/reagent_containers/food/snacks/donkpocket/honk/warm,
	/obj/item/seed/alien,
	/obj/item/boarvessel,
	/obj/item/boarvessel/forgery
)

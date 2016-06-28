/**
 *  pedestrian_geo_bdi
 *  Author: Geoffrey Danet
 *  Description: Based on the Pedestrian model made by Carole Adam.
 */


model pedestrian_geo_bdi


import "../modelAPIA.gaml"


/***************************
 * PEDESTRIANS / RESIDENTS *
 ***************************/

species pedestrian_geo_bdi parent:pedestrian skills:[moving] control: simple_bdi schedules: (pedestrian_geo_bdi where not (each.is_dead or each.is_safe))
{

	/*****************************
	 * PSYCHOLOGICAL  ATTRIBUTES *
	 *****************************/

	bool knows_risks <- flip(0.5); // define if the agent knows the risk related to fires
	bool knows_how_to_fight_fire <- flip(0.5); // define if the agent know how to fire a fire
	bool listens_radio <- false; // define if the agent is listening radio
	bool is_leaving <- false; // define if the agent is leaving to a shelter

	float determination min: 0.0 max: 1.0 <- rnd(1.0); // determination to do an action
	float persuadabillity min: 0.0 max: 1.0 <- rnd(1.0); // the agent can be more and less influenced by others agents or environment
	float danger_aversion min: 0.0 max: 1.0 <- rnd(1.0); // the agent can reject the fact that he is in a dangerous situation / is not effraid by the situation
	
	bool aware <- false; // define if the agent is aware of the fire

	/******
	 * BDI *
	 ******/

	// Belief
	predicate belief_danger <- new_predicate("Become dangerous");
	predicate belief_shelter_position <- new_predicate("Know shelter position");
	predicate belief_fire_position <- new_predicate("Know the fire position");

	// Desire & Intention
	predicate waiting_for_event <- new_predicate("Waiting for event") with_priority rnd(1-danger_aversion);
	predicate stay_alive <- new_predicate("Stay alive") with_priority escape_motivation ;
	predicate protect_property <- new_predicate("Protect their property") with_priority defend_motivation update: protect_property with_priority defend_motivation;
	predicate get_information <- new_predicate("Try to get information") with_priority rnd(danger_aversion);
	
	/********* */
	/** PLAN ***/
	/********* */

	/**
	 * Wait that something happen
	 */
	plan do_nothing intention: waiting_for_event when: not is_dead
	{
		self.color <- #blue;
	}

	// STAY ALIVE

	/**
	 * Go to the cloest shelter if it knows at least one shelter.
	 * If the agent doesn't knows shelters location it try to use an heuristic move
	 * If the agent is surrounded by fire, it will shelter at home.
	 */
	plan go_to_shelter intention: stay_alive when: not is_dead
	{
		self.is_leaving <- true;
		// True if the agent is surrounded by fires
		bool stuck <- not ((world_cell(location).neighbors) first_with (each.cover in [EMPTY_CELL]) != nil);
		// silver: covered at home, aqua: go to shelter
		self.color <- (stuck and not self.myBuilding.destroyed and location = myBuilding.location) ? #silver : #aqua;
		
		do remove_desire(protect_property); // loose all desire to defend its property

		do moving;
	}

	/**
	 * Get cover at home
	 * If the house is not burned and if the agent is at home
	 */
	plan take_cover_at_home intention: stay_alive when: not self.myBuilding.destroyed and (self.location = self.myBuilding.location) and not is_dead finished_when: self.myBuilding.destroyed
	{
		self.color <- #silver;
		do remove_desire(protect_property); // loose all desires to defend its property
	}

	// DEFENSE PROPERTY
	
	/**
	 * Seeks for informations about fire (futur work)
	 */
	plan seek_information intention: get_information when: not is_dead
	{
		self.color <- #green;
		listens_radio <- true;
	}

	/**
	 * Plan prepare property: if the agent knows how to fight fire, he can prepare the property before the fire come
	 */
	plan prepare_property when: (knows_how_to_fight_fire and empty(known_fires at_distance defense_radius) and !self.myBuilding.destroyed and  not is_dead)
	{
		self.color <- #orange;
		do prepare_for_fire;
	}
	
	/**
	 * Fight the fire if there are close fires around the property.
	 */
	plan fight_fire intention: protect_property
		when: (
			(
				not empty(known_fires at_distance defense_radius) // there are known fire in the defense radius
				and has_belief(belief_fire_position)) // And the agent has the believe about fire position 
				or (self.my_cell.cover in [HOTSPOT_CELL,FIRE_CELL]) // Or It is in fire/hot area
			) 
			and not is_dead
		finished_when: empty(known_fires at_distance defense_radius)
	{
		self.color <- #red;
		do fight_fire;
	}

 	/*****************
 	 * 	   REFLEXES       *
 	 *****************/

	/**
	 * The agent die when its health go bellow 0
	 */
	reflex death when: health<= 0 and !is_dead
	{
		do clear_beliefs();
        do clear_desires();
        do clear_intentions();
        rgb mem <- self.color;
 		self.color <- #black;
 		self.border <- mem;
		self.is_dead <- true;
		numberDead <- numberDead+1;
	}

	/**
	 * Update the agent status:
	 * 	- Update known fires
	 * 	- Speed (velocity)
	 * 	- Desire (protect property and stay alive) 
	 */
	reflex update_status when: !is_dead
	{
		// update known fires
		list<fire> new;
		loop current_fire over: known_fires
		{
			if(not dead(current_fire) and current_fire != nil and current_fire.intensity>0)
			{
				add current_fire to: new;
			}
		}
		known_fires <- copy(new);

		// If there aren't known fires remaining. Then, the agent doesn't belief he knows where are the fires anymore.
		if(empty(known_fires))
		{
			do remove_belief(belief_fire_position);
		}

		if(has_desire(protect_property) and not is_leaving and self.myBuilding.destroyed)
		{
			listens_radio <- false;
 			do remove_desire(protect_property);
			do add_desire(stay_alive);
 		}
	}


	/*****************
	 *    PERCEPTION    *
	 *****************/
	 
	/**
	 * The agent perceives an unknown fire in its perception area
	 */
	perceive target:(list(fire) - known_fires) in: perception_radius when: !is_dead
	{
		add self to: myself.known_fires;
	    ask myself
	    {
	    	do add_belief(belief_fire_position);
	    	do add_desire(get_information);
		}
	}

	/**
	 * The agent perceives a known fire which consider as a threat
	 */
	perceive target: known_fires in: danger_radius when: has_belief(belief_fire_position) and !is_dead
	{
		ask myself
		{
			aware <- true;
			do add_belief(belief_danger);
			do add_desire(protect_property);
	    	do add_desire(stay_alive);
		}
	}

	/**
	 * The agent perceives a shelter in its perception area
	 */
	perceive target: shelter in: perception_radius when: !is_dead
	{
		add self to: myself.known_shelters;
		myself.closest_shelter <- nil;
	}

	/**
	 * If the agent want leave but does not know shelters' position, he can look around in order to follow another agent
	 * which seems to know where to go. 
	 */
	perceive target: pedestrian_geo_bdi in: perception_radius when: empty(known_shelters) and self.is_leaving and !is_dead
	{
		if(self.is_leaving and not self.is_dead and not empty(self.known_shelters))
		{
			pedestrian_geo_bdi focus <- self;
			ask myself
		    {
		    	if(flip(persuadabillity)) // if the target influence or not the agent 
		    	{
		    		do goto target: focus; // Wait  ! Please !
		    	}
			}
		}
	}

	/**
	* If an agent is in a shelter area, it is safe
	*/
	perceive target:shelter in: 2 when: !is_dead
	{
		ask myself
	    {
	    	do clear_beliefs();
       	 	do clear_desires();
        	do clear_intentions();
	    	if(!is_safe)
	    	{
	    		numberSheltered <- numberSheltered+1;
	    	}
			self.is_safe <- true;
			self.color <- #lime;
		}
	}

	/******************
	 *  ASPECT FOR GUI  *
	 ******************/

	/**
	 * Define the agent aspect
	 */
	aspect basic
	{
		draw circle(size) color: color border: border;
	}

	
	init
	{
		self.speed <- velocity; // the speed correspond to its velocity
		ask shelter
		{
			if(flip(0.8)) // the agent has 80% chance to know this shelter
			{
				add self to: myself.known_shelters;
			}
		}
		do add_desire(waiting_for_event);
	}
}

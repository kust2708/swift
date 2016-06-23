/**
 *  pedestrianAPIA
 *  Author: carole
 *  Description: 
 */


model pedestrianAPIA


import "modelAPIA.gaml"


/***************************
 * LES PIETONS / HABITANTS *
 ***************************/
 
species pedestrian control: fsm { 
	
	/***********************
	 * PHYSICAL ATTRIBUTES *
	 ***********************/
	// health, initially random value, then updated by fire dealing injuries
	int health <- 100+rnd(100) min:0;
	// total received injury because no memory of initial health
	int injuries <- 0;
	
	// standard attributes
	rgb color <- #blue;
	float size <- 2.0;
	world_cell my_cell;
	building myBuilding;
	
	// state before dying or surviving
	string state_before_end <- "alive";
	
	/**************************
	 * GEOGRAPHICAL VARIABLES *
	 * updated each cycle     *
	 * used for computing     * 
	 * cognitive attributes   *
	 **************************/
	world_cell closest_hot_cell <- nil update: ((world_cell where (each.cover=HOTSPOT_CELL)) closest_to self);
	int distance_closest_hot update: (closest_hot_cell=nil)?1000:int(self distance_to closest_hot_cell);
	world_cell closest_fire_cell <- nil update: ((world_cell where (each.cover=FIRE_CELL)) closest_to self);
	int distance_closest_fire update: (closest_fire_cell=nil)?1000:int(self distance_to closest_fire_cell);
	

	/************************
	 * COGNITIVE ATTRIBUTES *
	 ************************/

	/* *** 0 *** OBJECTIVE ABILITY *** *** */
	
	// objective ability = how much he actually can deal with it 
	// impacts the effect of preparation actions (boost to health points and building resistance)
	// impacts the effect of defense actions (decrease in fire intensity) and the detection radius
	float objective_ability <- rnd_float(1);

	/*** 1 *** DANGER DETECTION / AWARENESS *** ***/
		
	// TODO : compter les feux ponderes par leur intensité dans le rayon de perception
	// int number_fires_aware <- length(fire at_distance(radius_aware));	
	// TODO actually keep a list of fires the individual is aware of (used to compute subjective danger)
	list<fire> known_fires <- [];
	bool aware {
		return length(known_fires)>0;	
	}
	
	// subjective danger function of known fires, 0-1 range
	// distance to fires is in 1-15 radius (max perception radius is 15)
	// intensity is also in 1-15 radius
	// sum over all fires, but if goes over 1, normalised back to 1
	float subjective_danger {
		return min([1,sum(  (known_fires where !dead(each)) collect (each.intensity/(each distance_to self+1))   )]); 
	}
	
	// objective danger function of all fires, 0-1 range, same computation
	// so if the individual is aware of all fires in his impact radius, he has the right estimation of danger
	float objective_danger {
		// objective danger is null in shelters (even if fires around)
		if (my_cell.cover = SHELTER_CELL) { // or if (state="safe")
			return 0;
		}
		// else compute actual objective danger from fires around
		return min([1,sum(  (fire at_distance people_further_awareness) collect (each.intensity/(each distance_to self))   )]); 
	}
	
	/*** 2 *** DANGER AVERSION : ESCAPE *** ***/
	
	// motivation to escape = subjective ability to escape / risk aversion / laziness to leave...
	// used in computing radius of aversion
	// initial random escape motivation
	float escape_motivation <- rnd_float(1);
	
	// number of fires replaced with subjective danger
		
	// objective ability to escape (has a car, knows shelters, etc)
	// impacts speed of escape and randomness/optimality of routing to shelter
	// FIXME: de-Simplification: now different from objective ability
	float objective_escapability <- rnd_float(1);
	// TODO replace with escape_impossible, and add subjective escapibility?
	
	// TODO subjective escapability?
	// only possible if the path is not in the cells but in the agent's mind... 
	
	// impossibility to escape: no empty cell has a possible route to shelter 
	// triggers transition from prepare_escape to prepare_defend
	// maximises motivation to defend
	// = objective escapability ? but dual, yes/no only
	bool escape_impossible <- false update: length(my_cell.neigh where (each.distance!=-1 or each.emergency_distance!=-1))=0;
	

	/*** 3 *** MOTIVATION : DEFEND *** ***/
		
	// initial motivation to defend, then dynamically updated 
	//  - high initial value = could come from wanting to defend one's livelihood
	//  - also subjective ability: if believes to be capable, then is motivated to do so
	//  - impacted by health (ability) and resistance of building (ability: protection, motivation: nothing to defend when down) 
	// this motivation impacts the proba to fight
	float initial_defend_motivation <- rnd_float(1);	
	
	// subjective ability to defend
	// will be updated based on performance feedback (success/failure at fighting fires)
	float subjective_defend_ability <- rnd_float(1);
	
	// defend motivation is the average between ability and motivation
	float defend_motivation <- mean([subjective_defend_ability,initial_defend_motivation]);
	
	/************************
	 * PERFORMANCE FEEDBACK *
	 ************************/
	 
	 
	// simulation cycles spent defending (used in computing performance)
	int cyclesInDefense <- 0;
	
	// number of fires extinguished
	// used to update subjective_ability (not stored), ie defend_motivation (indirectly)
	int number_fires_ext <- 0;

	// damage dealt to fires (reduction of intensity)
	float fighting_actions <- 0.0;
	

	/*********************
	 * HISTORIC OF PEOPLE *
	 *********************/ 
 	
 	// historic will contain : 
 	// state, distanceClosestHotWhenEntering, healthEntered, deltaHealth, nbCycleInTheState
 	list<list> historic <- [];
 	int index_of_cycle <- 4;
 	int index_of_health <- 3;
 
 	action historic_initialization {
		add [state, distance_closest_hot, health, health, 0] to: historic;			
 	}
 	 	
 	action historic_new_state {
		int past_health <- last(historic)[index_of_health] as int;
		put (health - past_health) in: last(historic) at: index_of_health;			
		add [state, distance_closest_hot, health, health, 0] to: historic;	 		
 	}
 	
 	action historic_update {
		int nbCycle <- last(historic)[index_of_cycle] as int;
		put (nbCycle + 1) in: last(historic) at: index_of_cycle;	
 	}
 	
 	action historic_save {
		// save the values of the variables name, speed and size to the csv file
		save "" + self + " " + historic to: save_trajectory_file_path type:"text"; 	
		// also write in the p.txt file for analysis
		save "" + self + " " + historic to: save_traj_for_analysis type:"text"; 	
		// and in the console
		//write "" + self + " " + historic;						
 	}
 	
 	
 	/***********************
 	 * PERCEPTION OF FIRES *
 	 ***********************/
 	
 	// FIRST reflex = perceive, which updates list of known fires and therefore subjective danger
	// is the individual aware of fires? perception action called in unaware state, replaced with reflex
	// once the fire enters the awareness radius (parameter), probability to detect depends on objective ability and max proba of detection (param)
	// outside of the radius, noone can perceive the fire (directly, but could be informed by others)
	reflex perceive_fires {
		// remove dead fires (no intensity anymore)
		ask (known_fires where dead(each)) {
			remove self from: myself.known_fires;
		}
 		// consider all fires in perception radius (param) that are not known yet
 		ask ((fire at_distance people_further_awareness)-known_fires) {
 			// probability to detect, moderated by objective ability of individual
 			if (flip(proba_detection*myself.objective_ability)) {
 				//write("individual "+myself.name+" detects fire "+self.name);
 				add self to: myself.known_fires;
 			}
 		} 		
 	}
 	
 	
 	/*****************
 	 * DEAD OR ALIVE *
 	 *****************/
	 
 	// SECOND reflexes : die (during fire) or survive (at the end of fire)
 	 
	// can die from any state
	reflex dying when: (state!="dead" and health<= 0) {
		//write("pedestrian from "+state+" is dying... injuries="+injuries);
		health <- 0;
		state_before_end <- state;
		state <- "dead";
	}
	
	// survive at the end if not dead and no more fires
	// note: fires can be stopped manually at any time to stop the simulation
	reflex survive when: state != "dead" and length(fire)=0 {
		// no more fires at a distance of 10? no fires at all? end of simulation?
		//write("pedestrian survived from "+state);
		state_before_end <- state;
	 	state <- "survivor";
	}
 	
 	
 	
  	/**********************
 	 * UPDATE MOTIVATIONS *
 	 *   MAKE DECISION    * 
 	 **********************/
 
 	// THIRD reflexes = update all motivations to make decision
 	
 	// when motivation decreases, it is multiplied by 1-motivation_update_rate (param), 
 	// if rate=0, no update in motiv; if rate=1, max update, motiv drops to 0; so stays in 0-1
 	float decrease_by_rate (float motiv, float rate) {
 		return motiv*(1-rate);
 	}

	// when motivation increases, it is added to (1-motiv)*motiv_update_rate, so stays in 0-1
	// if rate=0, nothing added, no update; if rate=1, adds 1-a, motiv raises to 1; so stays in 0-1
	float increase_by_rate (float motiv, float rate) {
		return motiv+(1-motiv)*rate;
	} 	
 	
 	// motivation to fight / subjective ability to fight
 	// TODO in future works: add other influences than ability in motivation
 	// compter les feux éteints autour ?
 	reflex update_motiv_fight when: state!="dead" and state!="safe" and state!="escape" {
 		//write("update fight motiv at cycle = "+cyclesInDefense);
 			
 		// special case: building collapsed: no need to defend anymore
 		if (myBuilding.resistance = 0) {
 			//write("zero resistance == zero motiv");
 			defend_motivation <- 0.0;
 		}
 		// special case: escape is impossible: highest motivation to defend 
 		else if (escape_impossible) {
 			//write("no escape == max motiv");
 			defend_motivation <- 1.0;
 		}
 		// initial case (no performance measured yet): only depends on initial motivation and subjective capability
 		else if (cyclesInDefense=0) {
 			defend_motivation <- mean([subjective_defend_ability,initial_defend_motivation]);
 			//write("initial avg motiv = "+defend_motivation);
 		}
 		else {//cycles in defense > 0
 			// factors influencing motivation
 			// injuries wrt total health
 			float injury_per_cycle <- injuries/cyclesInDefense;
 			float cycles_before_death <- (injury_per_cycle>0)?health/injury_per_cycle:1000000;
 			
 			// damage to building wrt total resistance
 			float damage_per_cycle <- myBuilding.damage / cyclesInDefense;
 			float cycles_before_destroyed <- (damage_per_cycle>0)?myBuilding.resistance/damage_per_cycle:1000000;
 			
 			// fighting actions wrt total intensity
 			float water_per_cycle <- fighting_actions/cyclesInDefense;
 			float cycles_before_extinction <- (water_per_cycle>0)?sum((known_fires where !dead(each)) collect each.intensity)/water_per_cycle:1000000;
 			
			// FIXME should depend on subjective ability !! not just on objective observation of damage 			
 			
 			// if gonna die before extinguishing the fire: decreases the motivation at specified rate (param)
 			if (min([cycles_before_death,cycles_before_destroyed]) < cycles_before_extinction) {
 				defend_motivation <- decrease_by_rate(defend_motivation,motivation_update_rate);
 			}
 			// else increase it (good performance feedback)
 			else {
 				defend_motivation <- increase_by_rate(defend_motivation,motivation_update_rate);
 			}
		}//end else
			// TODO: take into account neighbours behaviour and performance
			// TODO: take into account information / evacuation orders from authorities
 	}//end reflex
 	
 	
 	// update abilities by comparing observed actions with expected actions
	reflex update_subjective_ability when: state!="dead" and state!="safe" and state!="escape" {

			// expected effect on fire - since start of defense - each known fire decreases based on subjective ability
			float expected_fire_effect <- cyclesInDefense*subjective_defend_ability*people_fighting_factor*length(known_fires);
			
			// observed effect on fire - since start of defense
			float observed_fire_effect <- fighting_actions;
			 			
			// if does better than expected, increase confidence
			if (observed_fire_effect > expected_fire_effect) {
				subjective_defend_ability <- increase_by_rate(subjective_defend_ability,ability_update_rate);
			} 			
			// if does worse: decrease confidence / subjective ability
			else {
				subjective_defend_ability <- decrease_by_rate(subjective_defend_ability,ability_update_rate);
			}

		
	} 	

	// motivation to escape - depend de la vulnerabilite attendue sur la route
	reflex update_motiv_escape when: state!="dead" and state!="safe" and state!="escape" {
 		// special case: building collapsed: max motiv to escape
 		if (myBuilding.resistance = 0) {
 			escape_motivation <- 1.0;
 		}
 		// special case: escape is impossible: no motivation to escape 
 		else if (escape_impossible) {
 			escape_motivation <- 0.0;
 		}	
 		// if building not collapsed but escape still possible 
		else {//
			// if subjective danger is high, increase motivation to escape
			if (subjective_danger() > 0.5) {//
				escape_motivation <- increase_by_rate(escape_motivation,motivation_update_rate);
			}//
			// if subjective danger is low, decrease motivation to escape
			else {//
				escape_motivation <- decrease_by_rate(escape_motivation,motivation_update_rate);
			}
		}
		// TODO: separate motivation to escape and ability to do so (knows how to drive, knows some shelters, knows a path to them)		
		// TODO: fonction de preparedness de myBuilding, lifePoints de myBuilding, 
		// TODO: fonction du nombre et statut des voisins people, imitation, trust, emotion contagion
		// TODO: function of evacuation orders from authorities / norm / prescribed behaviour, and trust in them
	}//
	
	// decision = defend or escape depending on the highest motivation
	// will influence transitions between states in the fsm
	
	
	/*******************************************************************
	 * ACTIONS of RESIDENTS                                            *
	 *    - prepare (for now, same preparation for escape and defense) *
	 *    - defend (fight fire)                                        *
	 *    - escape (towards closest shelter)                           *
	 *******************************************************************/

 	// prepare house (add resistance) and self (add health) before fire too close
 	action prepare_for_fire {
 		// moderate preparation effect with objective ability of the individual
 		int preparationEffect <- int(rnd_float(people_preparation_factor*objective_ability));
 		// prepare house, based on objective ability - will protect it from fire damage
		ask myBuilding {
			// add life points by preparing for fire, until it gets closer
			// each action adds 0-10 points, but done several times
			resistance <- min([building_max_resistance,resistance+preparationEffect]);
		}
		health <- min([health+preparationEffect,max_health]);
 	}
 	
 	// fight fire in an action radius based on objective ability
 	action fight_fire {
 		//write "fight fires !";
 		// self effect on fire is moderated by objective ability
 		int fightingEffect <- int(rnd_float(people_fighting_factor*objective_ability));
		// actually fight the fire - influenced by objective ability
		ask fire at_distance (people_defense_radius) {
			// objective ability influences the target radius, and intensity decrement applied to fires in that radius
			myself.fighting_actions <- myself.fighting_actions + fightingEffect;
			intensity <- intensity - fightingEffect;
			shape <- circle(intensity);
			if (intensity < 0) {
				myself.number_fires_ext <- myself.number_fires_ext+1;
				// remove from list of known fires (counted in computing subjective danger)
				remove self from: myself.known_fires;
			}
		}
		
		// TODO return a boolean for success or failure, used to update subjective ability?
 	}

	// function to compute next cell of escapers 
	world_cell next_cell {
		//write ("current cell = "+my_cell);
		world_cell next_p <- my_cell;
		// objective ability to escape = chance to get the best cell
		if (flip(objective_escapability)) {
			next_p <- my_cell.neigh with_min_of(each.distance);
		}
		// else get a random neighbour cell (could move randomly and take longer to escape)
		else {
			next_p <- one_of(my_cell.neigh);
		}
		//write ("next cell = "+next_p);
		if(next_p != nil) {
			return next_p;
		}
		else {
			return my_cell;
		}
	}
	
	// action to escape, called from escape state
	action escape_towards_shelter {
		// first move
		my_cell <- next_cell();
		// second move if good abilities, to simulate extra speed
		if (flip(objective_escapability)) {
			// do it again
			my_cell <- next_cell(); 
		}
		// actually move to that next cell
		location <- my_cell.location;
	}




	/********************
	 * STATES OF PEOPLE *
	 ********************/

	/**************************
	 * INITIAL STATES :       *
	 *    - PASSIVE UNAWARE   *
	 *    - AWARE INDECISIVE  *
	 **************************/

	// initial state = objective danger (there are fires) but not yet aware/active 
	// danger awareness is updated at each step by monitoring fires in awareness radius
	state unaware initial: true{//
		enter {
			//color <- #darkblue;
			do historic_initialization;
		}
		do historic_update;
		// perception of fires is done by reflex and influences the boolean aware		
		
		// transitions to aware indecisive once becomes aware (known_fires is not empty)
 		transition to: active_indecisive when: aware() ;	
	}

	// first reaction when subjective danger: get active but indecisive about WHAT to do
	// look for more info to update the two opposite motivations
	state active_indecisive {
		enter {
			color <- #pink;
			numberIndecisive <- numberIndecisive+1;
			do historic_new_state;		
		}
		do historic_update;
		
		// additional monitoring behaviour to update variables: done by reflex
		
		// choice to defend depending on motivation (the higher the better)
		transition to: prepare_to_defend when: flip(defend_motivation);
 		// choice to escape depending on perceived ability to do so
 		transition to: prepare_to_escape when: flip(escape_motivation) ;
  		// others just stay indecisive until subjective_escapability grows
	
		exit {
			numberIndecisive <- numberIndecisive-1;
		}
	}



	/****************************
	 * DEFENDERS STATES         *
	 *   - preparing to defend  *
	 *   - actively defending   *
	 ****************************/
	 
	// preparing to defend property: train, prepare house and equipment, monitor
	state prepare_to_defend {
		enter {
			color <- #orange;
 			int past_health <- last(historic)[index_of_health] as int; //not used?
			do historic_new_state;				
 		}
		do historic_update;			
		
		// prepare house and self for fire
		do prepare_for_fire;
		
		// start to defend when fire reaches the house / defense radius (param)
		transition to: defend when: distance_closest_hot <= people_defense_radius;
	} 
	 
	// active defense of property when fire gets close enough
	state defend {
		enter {
			color <- #red; 	
			numberDefenders <- numberDefenders+1;
			//defender <- true;
			do historic_new_state;		
 		}
		do historic_update;		
		
		// incrementer le temps passe a defendre
		cyclesInDefense <- cyclesInDefense+1;		
		do fight_fire;
		
		// monitor to update subjective_danger and motivations based on this danger: reflexes
		
		// back to prepare when no more fires at required distance
		transition to: prepare_to_defend when: distance_closest_hot > people_defense_radius; 
		
		// escape when motivation to escape is bigger than motivation to fight (too dangerous)
		transition to: escape when: escape_motivation>defend_motivation {
			numberDefended <- numberDefended+1;
			color <- #purple;
		} 	
	}



	/****************************************************
	 * ESCAPERS STATES                                  *
	 *    - preparing to escape (finish business, etc)  *
	 *    - actually escaping (after trigger)           *
	 ****************************************************/
	
	// preparing to escape, finishing business before (wait and see, etc)
	state prepare_to_escape {
		enter {
			color <- #yellow;
			do historic_new_state;				
 		}
		do historic_update;
		
		// actually prepare (raise health and resistance)
		do prepare_for_fire;
			
		// escape when ready = sufficient preparation achieved AND still motivated (fire could have disappeared by then)
		transition to: escape when: myBuilding.resistance>building_fire_ready and escape_motivation>0.5;

		// escape when surprised by fire, too close when not ready yet
		transition to: escape when: (distance_closest_hot <= people_defense_radius) ;
		
		// if impossible to reach shelter, has to defend		
		transition to: prepare_to_defend when: escape_impossible  {
			write("prepare to escape but IMPOSSIBLE !!");
		}

	}
	
	// state of people who are actually escaping towards a shelter
	state escape {
		enter {
			color <- #aqua; 
			numberEscapers <- numberEscapers+1;	
			//escaper <- true;
			
			do historic_new_state;		
 		}
	
		do historic_update;
			
		do escape_towards_shelter;
		// TODO: special state when needs to take emergency shelter in any building/lake ?
		
		// only stops when reaching shelter
		transition to: safe when: (my_cell.cover = SHELTER_CELL) {
			color <- #green;
			//write (name+" reaches shelter");
			numberSheltered <- numberSheltered +1;
		}	
	}
	

	/********************************
	 * FINAL STATES :               *
	 *   - SAFE in shelter (fire)   *
	 *   - dead from any state      *
	 *   - survivor from any state  *
     ********************************/
	
	// TODO: dans le exit de chaque state, enregistrer dans une variable previousState l'etat dont on sort
	// OU incrementer des compteurs dans les reflexes survive/dying
	state safe  {
		// agent disappear NO
		//do die;
		enter {
			color <- #green;
			do historic_new_state;		
 		}
 
		do historic_update;
		
		transition to: survivor when: length(fire)=0;
	}
	
	// state of people who died during the fire
	state dead final: false{
		enter {
			// peint en noir mais cadavre laisse sur place pour analyse
			color <- #black;
			numberDead <- numberDead+1;
			//write (string(cycle)+" agent "+name+" dies");
			do historic_new_state;		
			do historic_save;	
 		}
		//	do historic_update;	
	}
	
	
	state survivor final:true {	
		enter {
			color <- #green;
			do historic_new_state;	
			do historic_save;			
 		}
 		
	//	do historic_update;		
	}
	

	/******************
	 * ASPECT FOR GUI *
	 ******************/
	
	aspect basic {
		draw circle(size) color: color;
	}	
}



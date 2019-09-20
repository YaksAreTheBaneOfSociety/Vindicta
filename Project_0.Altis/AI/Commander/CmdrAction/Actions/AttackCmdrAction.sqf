#include "..\..\common.hpp"

/*
Class: AI.CmdrAI.CmdrAction.Actions.AttackCmdrAction
Base class for CmdrAI attack action types.

TODO: refactor out commonality for actions that consist of a detachment and a target.
Or at least share functionality via a library or something.

Parent: <CmdrAction>
*/
CLASS("AttackCmdrAction", "CmdrAction")
	// Garrison ID the attack originates from
	VARIABLE("srcGarrId");
	// Target (see CmdrAITarget.sqf), an AST_VAR wrapper
	VARIABLE("targetVar");
	// Flags to use when splitting off the detachment to perform the attack, an AST_VAR wrapper
	VARIABLE("splitFlagsVar");
	// Efficency of the detachment, an AST_VAR wrapper
	VARIABLE("detachmentEffVar");
	// Garrison ID of the detachment performing the attack, an AST_VAR wrapper
	VARIABLE("detachedGarrIdVar");
	// Start date for the attack action, an AST_VAR wrapper
	VARIABLE("startDateVar");

	// Target to RTB to after the attack, an AST_VAR wrapper
	VARIABLE("rtbTargetVar");

#ifdef DEBUG_CMDRAI
	VARIABLE("debugColor");
	VARIABLE("debugSymbol");
#endif

	/*
	Constructor: new

	Creates a new AttackCmdrAction originating from the specified source garrison.

	Parameters:
	  _srcGarrId - Number, the <Model.GarrisonModel> Id of the source garrison that should perform the attack.
	*/
	METHOD("new") {
		params [P_THISOBJECT, P_NUMBER("_srcGarrId")];

		T_SETV("srcGarrId", _srcGarrId);

		// Start date for this action, default to immediate
		private _startDateVar = MAKE_AST_VAR(DATE_NOW);
		T_SETV("startDateVar", _startDateVar);

		// Desired detachment efficiency changes when updateScore is called. This shouldn't happen once the action
		// has been started, but this constructor is called before that point.
		private _detachmentEffVar = MAKE_AST_VAR(EFF_ZERO);
		T_SETV("detachmentEffVar", _detachmentEffVar);

		// Target could be modified during the action (redirect etc.).
		private _targetVar = T_CALLM("createVariable", [[]]);
		T_SETV("targetVar", _targetVar);

		// RTB target can be modified during the action, if the src garrison dies or something.
		private _rtbTargetVar = T_CALLM("createVariable", [[]]);
		T_SETV("rtbTargetVar", _rtbTargetVar);

		// Flags to use when splitting off the detachment garrison		
		private _splitFlagsVar = T_CALLM("createVariable", [[ASSIGN_TRANSPORT]]);
		T_SETV("splitFlagsVar", _splitFlagsVar);
	} ENDMETHOD;

	METHOD("delete") {
		params [P_THISOBJECT];

		{ DELETE(_x) } forEach T_GETV("transitions");

#ifdef DEBUG_CMDRAI
		deleteMarker (_thisObject + "_line");
		deleteMarker (_thisObject + "_label");
#endif
	} ENDMETHOD;

	/* protected override */ METHOD("createTransitions") {
		params [P_THISOBJECT];

		T_PRVAR(srcGarrId);
		T_PRVAR(detachmentEffVar);
		T_PRVAR(splitFlagsVar);
		T_PRVAR(targetVar);
		T_PRVAR(startDateVar);
		T_PRVAR(rtbTargetVar);

		// Call MAKE_AST_VAR directly because we don't won't the CmdrAction to automatically push and pop this value 
		// (it is a constant for this action so it doesn't need to be saved and restored)
		private _srcGarrIdVar = MAKE_AST_VAR(_srcGarrId);

		// Split garrison Id is set by the split AST, so we want it to be saved and restored when simulation is run
		// (so the real value isn't affected by simulation runs, see CmdrAction.applyToSim for details).
		private _splitGarrIdVar = T_CALLM("createVariable", [MODEL_HANDLE_INVALID]);
		T_SETV("detachedGarrIdVar", _splitGarrIdVar);

		// INITIALIZE THE ACTION STATE TRANSITIONS WE CAN USE IN THE ACTION
		// First we will split off the required detachment garrison
		private _splitAST_Args = [
				_thisObject,						// This action (for debugging context)
				[CMDR_ACTION_STATE_START], 			// First action we do
				CMDR_ACTION_STATE_SPLIT, 			// State change if successful
				CMDR_ACTION_STATE_END, 				// State change if failed (go straight to end of action)
				_srcGarrIdVar, 						// Garrison to split (constant)
				_detachmentEffVar, 					// Efficiency we want the detachment to have (constant)
				_splitFlagsVar, 					// Flags for split operation
				_splitGarrIdVar]; 					// variable to recieve Id of the garrison after it is split
		private _splitAST = NEW("AST_SplitGarrison", _splitAST_Args);

		// Assign the action we are performing to the detachment garrison (so it is marked as busy for other actions)
		private _assignAST_Args = [
				_thisObject, 						// This action, gets assigned to the garrison
				[CMDR_ACTION_STATE_SPLIT], 			// Do this after splitting
				CMDR_ACTION_STATE_READY_TO_MOVE, 	// State change when successful (can't fail)
				_splitGarrIdVar]; 					// Id of garrison to assign the action to
		private _assignAST = NEW("AST_AssignActionToGarrison", _assignAST_Args);

		// Perform the attack itself (this allows the garrison to decide how to move to the target)
		private _attackAST_Args = [
				_thisObject,
				[CMDR_ACTION_STATE_READY_TO_MOVE], 	// Once we are split and assigned the action we can go
				CMDR_ACTION_STATE_RTB_SELECT_TARGET,// State when we succeed, it leads to selecting new target (usually home)
				CMDR_ACTION_STATE_END, 				// If we are dead then go to end
				CMDR_ACTION_STATE_RTB_SELECT_TARGET,// If we timeout then RTB
				_splitGarrIdVar, 					// Id of the garrison doing the attacking
				_targetVar, 						// Target to attack (cluster or garrison supported)
				MAKE_AST_VAR(200)];					// Move radius
		private _attackAST = NEW("AST_GarrisonAttackTarget", _attackAST_Args);

		// private _rtbMoveAST_Args = [
		// 		_thisObject, 						// This action (for debugging context)
		// 		[CMDR_ACTION_STATE_READY_TO_MOVE], 		
		// 		CMDR_ACTION_STATE_MOVED, 			// State change when successful
		// 		CMDR_ACTION_STATE_END,				// State change when garrison is dead (just terminate the action)
		// 		CMDR_ACTION_STATE_RTB_SELECT_TARGET,// State change when target is dead, we RTB
		// 		_splitGarrIdVar, 					// Id of garrison to move
		// 		_targetVar, 						// Target to move to (initially the target cluster)
		// 		MAKE_AST_VAR(200)]; 				// Radius to move within
		// private _rtbMoveAST = NEW("AST_MoveGarrison", _rtbMoveAST_Args);

		// TODO: write AST to select a new combat target that is already engaged so we can act as backup
		// Select an RTB target after the attack, or when the current one is destroyed or otherwise not valid
		private _newRtbTargetAST_Args = [
				[CMDR_ACTION_STATE_RTB_SELECT_TARGET],
				CMDR_ACTION_STATE_RTB, 				// RTB after we selected a target
				_srcGarrIdVar, 						// Originating garrison (default we return to)
				_splitGarrIdVar, 					// Id of the garrison we are moving (for context)
				_rtbTargetVar]; 					// New target
		private _newRtbTargetAST = NEW("AST_SelectFallbackTarget", _newRtbTargetAST_Args);

		// Return to base
		private _rtbAST_Args = [
				_thisObject, 						// This action (for debugging context)
				[CMDR_ACTION_STATE_RTB], 			// Required state
				CMDR_ACTION_STATE_RTB_SUCCESS, 		// State change when successful
				CMDR_ACTION_STATE_END,				// State change when garrison is dead (just terminate the action)
				CMDR_ACTION_STATE_RTB_SELECT_TARGET,// State change when target is dead. We will select another RTB target
				_splitGarrIdVar, 					// Id of garrison to move
				_rtbTargetVar, 						// Target to move to (initially the target cluster)
				MAKE_AST_VAR(200)]; 				// Radius to move within
		private _rtbAST = NEW("AST_MoveGarrison", _rtbAST_Args);

		// Merge back to the source garrison (or whatever RTB target was chosen instead)
		private _mergeBackAST_Args = [
				_thisObject,
				[CMDR_ACTION_STATE_RTB_SUCCESS], 	// Merge once we reach the destination (whatever it is)
				CMDR_ACTION_STATE_END, 				// Once merged we are done
				CMDR_ACTION_STATE_END, 				// If the detachment is dead then we can just end the action
				CMDR_ACTION_STATE_RTB_SELECT_TARGET,// If the target is dead then reselect a new target
				_splitGarrIdVar, 					// Id of the garrison we are merging
				_rtbTargetVar]; 					// Target to merge to (garrison or location is valid)
		private _mergeBackAST = NEW("AST_MergeOrJoinTarget", _mergeBackAST_Args);

		// Return the ASTs as an array
		[_splitAST, _assignAST, _attackAST, _newRtbTargetAST, _rtbAST, _mergeBackAST]
	} ENDMETHOD;
	
	// Make a debug label from our properties
	/* protected override */ METHOD("getLabel") {
		params [P_THISOBJECT, P_STRING("_world")];

		T_PRVAR(srcGarrId);
		T_PRVAR(state);
		private _srcGarr = CALLM(_world, "getGarrison", [_srcGarrId]);
		private _srcEff = GETV(_srcGarr, "efficiency");

		private _startDate = T_GET_AST_VAR("startDateVar");
		private _timeToStart = if(_startDate isEqualTo []) then {
			" (unknown)"
		} else {
			private _numDiff = (dateToNumber _startDate - dateToNumber DATE_NOW);
			if(_numDiff > 0) then {
				private _dateDiff = numberToDate [0, _numDiff];
				private _mins = _dateDiff#4 + _dateDiff#3*60;

				format [" (start in %1 mins)", _mins]
			} else {
				" (started)"
			};
		};

		private _targetName = [_world, T_GET_AST_VAR("targetVar")] call Target_fnc_GetLabel;
		private _detachedGarrId = T_GET_AST_VAR("detachedGarrIdVar");
		if(_detachedGarrId == MODEL_HANDLE_INVALID) then {
			format ["%1 %2%3 -> %4%5", _thisObject, LABEL(_srcGarr), _srcEff, _targetName, _timeToStart]
		} else {
			private _detachedGarr = CALLM(_world, "getGarrison", [_detachedGarrId]);
			private _detachedEff = GETV(_detachedGarr, "efficiency");
			format ["%1 %2%3 -> %4%5 -> %6%7", _thisObject, LABEL(_srcGarr), _srcEff, LABEL(_detachedGarr), _detachedEff, _targetName, _timeToStart]
		};
	} ENDMETHOD;

	/*
	Function: (protected) updateIntelFromDetachment
	Parent classes can call this to update an intel item with the details
	of the detachment garrison.

	Parameters:
		_world - <Model.WorldModel>, the world model being used, should be the real world as we don't create intel for sim worlds.
		_intel - <Intel.IntelCommanderActionAttack>, the intel object to populate with info about the detachment performing the attack.
	*/
	/* protected */ METHOD("updateIntelFromDetachment") {
		params [P_THISOBJECT, P_OOP_OBJECT("_world"), P_OOP_OBJECT("_intel")];
		ASSERT_OBJECT_CLASS(_world, "WorldModel");
		ASSERT_OBJECT_CLASS(_intel, "IntelCommanderActionAttack");
		
		// Update progress of the detachment
		private _detachedGarrId = T_GET_AST_VAR("detachedGarrIdVar");
		if(_detachedGarrId != MODEL_HANDLE_INVALID) then {
			private _detachedGarr = CALLM(_world, "getGarrison", [_detachedGarrId]);
			SETV(_intel, "garrison", GETV(_detachedGarr, "actual"));
			SETV(_intel, "pos", GETV(_detachedGarr, "pos"));
			SETV(_intel, "posCurrent", GETV(_detachedGarr, "pos"));
			SETV(_intel, "strength", GETV(_detachedGarr, "efficiency"));
		};
	} ENDMETHOD;
	
	/* protected override */ METHOD("debugDraw") {
		params [P_THISOBJECT, P_STRING("_world")];

		T_PRVAR(srcGarrId);
		private _srcGarr = CALLM(_world, "getGarrison", [_srcGarrId]);
		ASSERT_OBJECT(_srcGarr);
		private _srcGarrPos = GETV(_srcGarr, "pos");

		private _targetPos = [_world, T_GET_AST_VAR("targetVar")] call Target_fnc_GetPos;

		T_PRVAR(debugColor);
		T_PRVAR(debugSymbol);

		[_srcGarrPos, _targetPos, _debugColor, 8, _thisObject + "_line"] call misc_fnc_mapDrawLine;

		private _centerPos = _srcGarrPos vectorAdd ((_targetPos vectorDiff _srcGarrPos) apply { _x * 0.25 });
		private _mrk = _thisObject + "_label";
		createmarker [_mrk, _centerPos];
		_mrk setMarkerType _debugSymbol;
		_mrk setMarkerColor _debugColor;
		_mrk setMarkerPos _centerPos;
		_mrk setMarkerAlpha 1;
		_mrk setMarkerText T_CALLM("getLabel", [_world]);

		// private _detachedGarrId = T_GET_AST_VAR("detachedGarrIdVar");
		// if(_detachedGarrId != MODEL_HANDLE_INVALID) then {
		// 	private _detachedGarr = CALLM(_world, "getGarrison", [_detachedGarrId]);
		// 	ASSERT_OBJECT(_detachedGarr);
		// 	private _detachedGarrPos = GETV(_detachedGarr, "pos");
		// 	[_detachedGarrPos, _centerPos, "ColorBlack", 4, _thisObject + "_line2"] call misc_fnc_mapDrawLine;
		// };
	} ENDMETHOD;

ENDCLASS;
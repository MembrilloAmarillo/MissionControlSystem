package xtce_parser

BOOLEAN_DATA_TYPE :: "BooleanDataType" 
BooleanDataType :: struct {
	base : BaseDataType,
	t_initialValue : xs_string,
	t_oneStringValue : xs_string,
	t_zeroStringValue : xs_string,

}

COMPARISON_LIST_TYPE :: "ComparisonListType" 
ComparisonListType :: struct {
	t_Comparison : [dynamic]ComparisonType,

}

EXTERNAL_ALGORITHM_SET_TYPE :: "ExternalAlgorithmSetType" 
ExternalAlgorithmSetType :: struct {
	t_ExternalAlgorithm : [dynamic]ExternalAlgorithmType,

}

RELATIVE_TIME_DATA_TYPE :: "RelativeTimeDataType" 
RelativeTimeDataType :: struct {
	base : BaseTimeDataType,
	t_initialValue : xs_duration,

}

BASE_ALARM_TYPE :: "BaseAlarmType" 
BaseAlarmType :: struct {
	t_AncillaryDataSet : AncillaryDataSetType,
	t_name : xs_string,
	t_shortDescription : ShortDescriptionType,

}

NUMERIC_ALARM_TYPE :: "NumericAlarmType" 
NumericAlarmType :: struct {
	base : AlarmType,
	t_StaticAlarmRanges : AlarmRangesType,
	t_ChangeAlarmRanges : ChangeAlarmRangesType,
	t_AlarmMultiRanges : AlarmMultiRangesType,

}

ARGUMENT_ASSIGNMENT_TYPE :: "ArgumentAssignmentType" 
ArgumentAssignmentType :: struct {
	t_argumentName : NameReferenceType,
	t_argumentValue : xs_string,

}

ARGUMENT_VARIABLE_STRING_TYPE :: "ArgumentVariableStringType" 
ArgumentVariableStringType :: struct {
	t_LeadingSize : LeadingSizeType,
	t_TerminationChar : xs_hexBinary,
	t_maxSizeInBits : PositiveLongType,
	t_choice_0 : t_ArgumentVariableStringType0,

}

t_ArgumentVariableStringType0:: union {
	ArgumentDiscreteLookupListType,
	ArgumentDynamicValueType,
}

TIME_ALARM_RANGES_TYPE :: "TimeAlarmRangesType" 
TimeAlarmRangesType :: struct {
	base : AlarmRangesType,
	t_timeUnits : TimeUnitsType,

}

MATH_OPERATION_CALIBRATOR_TYPE :: "MathOperationCalibratorType" 
MathOperationCalibratorType :: struct {
	base : BaseCalibratorType,
	t_choice_0 : [dynamic]t_MathOperationCalibratorType0,

}

t_MathOperationCalibratorType0:: union {
	ParameterInstanceRefType,
	MathOperatorsType,
	xs_string,
}

BASE_CALIBRATOR_TYPE :: "BaseCalibratorType" 
BaseCalibratorType :: struct {
	t_AncillaryDataSet : AncillaryDataSetType,
	t_name : xs_string,
	t_shortDescription : ShortDescriptionType,

}

META_COMMAND_TYPE :: "MetaCommandType" 
MetaCommandType :: struct {
	base : NameDescriptionType,
	t_BaseMetaCommand : BaseMetaCommandType,
	t_SystemName : xs_string,
	t_ArgumentList : ArgumentListType,
	t_CommandContainer : CommandContainerType,
	t_TransmissionConstraintList : TransmissionConstraintListType,
	t_DefaultSignificance : SignificanceType,
	t_ContextSignificanceList : ContextSignificanceListType,
	t_Interlock : InterlockType,
	t_VerifierSet : VerifierSetType,
	t_ParameterToSetList : ParameterToSetListType,
	t_ParametersToSuspendAlarmsOnSet : ParametersToSuspendAlarmsOnSetType,
	t_abstract : xs_boolean,

}

INPUT_SET_TYPE :: "InputSetType" 
InputSetType :: struct {
	t_choice_0 : [dynamic]t_InputSetType0,

}

t_InputSetType0:: union {
	ConstantType,
	InputParameterInstanceRefType,
}

ARGUMENT_ASSIGNMENT_LIST_TYPE :: "ArgumentAssignmentListType" 
ArgumentAssignmentListType :: struct {
	t_ArgumentAssignment : [dynamic]ArgumentAssignmentType,

}

PARAMETER_SET_TYPE :: "ParameterSetType" 
ParameterSetType :: struct {
	t_choice_0 : [dynamic]t_ParameterSetType0,

}

t_ParameterSetType0:: union {
	ParameterRefType,
	ParameterType,
}

BYTE_ORDER_TYPE :: "ByteOrderType" 
ByteOrderType :: struct {
	t_enumeration_values : []string,
	t_union : union {
		ByteOrderCommonType,
		ByteOrderArbitraryType,
	}
}

t_ByteOrderType_Enumeration := [?]string {  }

ALARM_MULTI_RANGES_TYPE :: "AlarmMultiRangesType" 
AlarmMultiRangesType :: struct {
	base : BaseAlarmType,
	t_Range : [dynamic]MultiRangeType,

}

MESSAGE_SET_TYPE :: "MessageSetType" 
MessageSetType :: struct {
	base : OptionalNameDescriptionType,
	t_Message : [dynamic]MessageType,

}

CHECK_WINDOW_TYPE :: "CheckWindowType" 
CheckWindowType :: struct {
	t_timeToStartChecking : RelativeTimeType,
	t_timeToStopChecking : RelativeTimeType,
	t_timeWindowIsRelativeTo : TimeWindowIsRelativeToType,

}

VERIFIER_SET_TYPE :: "VerifierSetType" 
VerifierSetType :: struct {
	t_TransferredToRangeVerifier : TransferredToRangeVerifierType,
	t_SentFromRangeVerifier : SentFromRangeVerifierType,
	t_ReceivedVerifier : ReceivedVerifierType,
	t_AcceptedVerifier : AcceptedVerifierType,
	t_QueuedVerifier : QueuedVerifierType,
	t_ExecutionVerifier : [dynamic]ExecutionVerifierType,
	t_CompleteVerifier : [dynamic]CompleteVerifierType,
	t_FailedVerifier : FailedVerifierType,

}

ARGUMENT_A_N_DED_CONDITIONS_TYPE :: "ArgumentANDedConditionsType" 
ArgumentANDedConditionsType :: struct {
	base : BaseConditionsType,
	t_choice_0 : [2][dynamic]t_ArgumentANDedConditionsType0,

}

t_ArgumentANDedConditionsType0:: union {
	ArgumentORedConditionsType,
	ArgumentComparisonCheckType,
}

SENT_FROM_RANGE_VERIFIER_TYPE :: "SentFromRangeVerifierType" 
SentFromRangeVerifierType :: struct {
	base : CommandVerifierType,

}

PARAMETER_TO_SET_LIST_TYPE :: "ParameterToSetListType" 
ParameterToSetListType :: struct {
	t_ParameterToSet : [dynamic]ParameterToSetType,

}

RADIX_TYPE :: "RadixType" 
RadixType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_RadixType_Enumeration := [?]string { "Decimal", "Hexadecimal", "Octal", "Binary",  }

STRING_CONTEXT_ALARM_TYPE :: "StringContextAlarmType" 
StringContextAlarmType :: struct {
	base : StringAlarmType,
	t_ContextMatch : ContextMatchType,

}

BINARY_DATA_TYPE :: "BinaryDataType" 
BinaryDataType :: struct {
	base : BaseDataType,
	t_initialValue : xs_hexBinary,

}

PHYSICAL_ADDRESS_SET_TYPE :: "PhysicalAddressSetType" 
PhysicalAddressSetType :: struct {
	t_PhysicalAddress : [dynamic]PhysicalAddressType,

}

FLOAT_ENCODING_SIZE_IN_BITS_TYPE :: "FloatEncodingSizeInBitsType" 
FloatEncodingSizeInBitsType :: struct {
	t_restriction : xs_unsignedShort,
	t_enumeration_values : []string,

}

t_FloatEncodingSizeInBitsType_Enumeration := [?]string { "16", "32", "40", "48", "64", "80", "128",  }

ARRAY_PARAMETER_TYPE :: "ArrayParameterType" 
ArrayParameterType :: struct {
	base : ArrayDataTypeType,
	t_DimensionList : DimensionListType,

}

PARAMETER_TO_SUSPEND_ALARMS_ON_TYPE :: "ParameterToSuspendAlarmsOnType" 
ParameterToSuspendAlarmsOnType :: struct {
	base : ParameterRefType,
	t_suspenseTime : RelativeTimeType,
	t_verifierToTriggerOn : VerifierEnumerationType,

}

INPUT_OUTPUT_TRIGGER_ALGORITHM_TYPE :: "InputOutputTriggerAlgorithmType" 
InputOutputTriggerAlgorithmType :: struct {
	base : InputOutputAlgorithmType,
	t_TriggerSet : TriggerSetType,
	t_triggerContainer : NameReferenceType,
	t_priority : xs_int,

}

FIXED_INTEGER_VALUE_TYPE :: "FixedIntegerValueType" 
FixedIntegerValueType :: struct {
	t_enumeration_values : []string,
	t_union : union {
		xs_integer,
		HexadecimalType,
		OctalType,
		BinaryType,
	}
}

t_FixedIntegerValueType_Enumeration := [?]string {  }

MATCH_CRITERIA_TYPE :: "MatchCriteriaType" 
MatchCriteriaType :: struct {
	t_choice_0 : t_MatchCriteriaType0,

}

t_MatchCriteriaType0:: union {
	InputAlgorithmType,
	BooleanExpressionType,
	ComparisonListType,
	ComparisonType,
}

FIXED :: "Fixed" 
Fixed :: struct {
	t_FixedValue : PositiveLongType,

}

ARGUMENT_COMPARISON_TYPE :: "ArgumentComparisonType" 
ArgumentComparisonType :: struct {
	t_comparisonOperator : ComparisonOperatorsType,
	t_value : xs_string,
	t_choice_0 : t_ArgumentComparisonType0,

}

t_ArgumentComparisonType0:: union {
	ArgumentInstanceRefType,
	ParameterInstanceRefType,
}

STRING_ALARM_LIST_TYPE :: "StringAlarmListType" 
StringAlarmListType :: struct {
	t_StringAlarm : [dynamic]StringAlarmLevelType,

}

BINARY_DATA_ENCODING_TYPE :: "BinaryDataEncodingType" 
BinaryDataEncodingType :: struct {
	base : DataEncodingType,
	t_SizeInBits : IntegerValueType,
	t_FromBinaryTransformAlgorithm : InputAlgorithmType,
	t_ToBinaryTransformAlgorithm : InputAlgorithmType,

}

RATE_IN_STREAM_TYPE :: "RateInStreamType" 
RateInStreamType :: struct {
	t_basis : BasisType,
	t_minimumValue : xs_double,
	t_maximumValue : xs_double,

}

REFERENCE_POINT_TYPE :: "ReferencePointType" 
ReferencePointType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_ReferencePointType_Enumeration := [?]string { "start", "end",  }

PARAMETER_TO_SET_TYPE :: "ParameterToSetType" 
ParameterToSetType :: struct {
	base : ParameterRefType,
	t_setOnVerification : VerifierEnumerationType,
	t_choice_0 : t_ParameterToSetType0,

}

t_ParameterToSetType0:: union {
	xs_string,
	MathOperationType,
}

ARGUMENT_ARRAY_ARGUMENT_REF_ENTRY_TYPE :: "ArgumentArrayArgumentRefEntryType" 
ArgumentArrayArgumentRefEntryType :: struct {
	base : ArgumentSequenceEntryType,
	t_DimensionList : ArgumentDimensionListType,
	t_argumentRef : NameReferenceType,
	t_lastEntryForThisArrayInstance : xs_boolean,

}

TRIGGERED_MATH_OPERATION_TYPE :: "TriggeredMathOperationType" 
TriggeredMathOperationType :: struct {
	base : MathOperationType,
	t_TriggerSet : TriggerSetType,
	t_outputParameterRef : NameReferenceType,

}

CONTAINER_REF_ENTRY_TYPE :: "ContainerRefEntryType" 
ContainerRefEntryType :: struct {
	base : SequenceEntryType,
	t_containerRef : NameReferenceType,

}

PARAMETER_SEGMENT_REF_ENTRY_TYPE :: "ParameterSegmentRefEntryType" 
ParameterSegmentRefEntryType :: struct {
	base : SequenceEntryType,
	t_parameterRef : NameReferenceType,
	t_order : PositiveLongType,
	t_sizeInBits : PositiveLongType,

}

ARGUMENT_BASE_DATA_TYPE :: "ArgumentBaseDataType" 
ArgumentBaseDataType :: struct {
	base : NameDescriptionType,
	t_UnitSet : UnitSetType,
	t_baseType : NameReferenceType,
	t_choice_0 : t_ArgumentBaseDataType0,

}

t_ArgumentBaseDataType0:: union {
	ArgumentStringDataEncodingType,
	IntegerDataEncodingType,
	FloatDataEncodingType,
	ArgumentBinaryDataEncodingType,
}

CONTEXT_CALIBRATOR_LIST_TYPE :: "ContextCalibratorListType" 
ContextCalibratorListType :: struct {
	t_ContextCalibrator : [dynamic]ContextCalibratorType,

}

FLOAT_DATA_TYPE :: "FloatDataType" 
FloatDataType :: struct {
	base : BaseDataType,
	t_ToString : ToStringType,
	t_initialValue : xs_double,
	t_sizeInBits : FloatSizeInBitsType,
	t_ValidRange : ValidRange,

}

ARGUMENT_STRING_DATA_TYPE :: "ArgumentStringDataType" 
ArgumentStringDataType :: struct {
	base : ArgumentBaseDataType,
	t_SizeRangeInCharacters : IntegerRangeType,
	t_initialValue : xs_string,
	t_restrictionPattern : xs_string,
	t_characterWidth : CharacterWidthType,

}

BYTE_ORDER_COMMON_TYPE :: "ByteOrderCommonType" 
ByteOrderCommonType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_ByteOrderCommonType_Enumeration := [?]string { "mostSignificantByteFirst", "leastSignificantByteFirst",  }

UNIT_FORM_TYPE :: "UnitFormType" 
UnitFormType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_UnitFormType_Enumeration := [?]string { "calibrated", "uncalibrated", "raw",  }

RELATIVE_TIME_TYPE :: "RelativeTimeType" 
RelativeTimeType :: struct {
	t_restriction : xs_duration,

}

NAME_TYPE :: "NameType" 
NameType :: struct {
	t_restriction : xs_normalizedString,

}

PERCENT_COMPLETE_TYPE :: "PercentCompleteType" 
PercentCompleteType :: struct {
	t_choice_0 : t_PercentCompleteType0,

}

t_PercentCompleteType0:: union {
	DynamicValueType,
	struct {
	t_base : xs_double,
	maxInclusive : string,
	minInclusive : string,
	},
}

BASE_CONDITIONS_TYPE :: "BaseConditionsType" 
BaseConditionsType :: struct {

}

ARGUMENT_ENUMERATED_DATA_TYPE :: "ArgumentEnumeratedDataType" 
ArgumentEnumeratedDataType :: struct {
	base : ArgumentBaseDataType,
	t_EnumerationList : EnumerationListType,
	t_initialValue : xs_string,

}

RATE_IN_STREAM_WITH_STREAM_NAME_TYPE :: "RateInStreamWithStreamNameType" 
RateInStreamWithStreamNameType :: struct {
	base : RateInStreamType,
	t_streamRef : NameReferenceType,

}

SHORT_DESCRIPTION_TYPE :: "ShortDescriptionType" 
ShortDescriptionType :: struct {
	t_restriction : xs_string,

}

CUSTOM_STREAM_TYPE :: "CustomStreamType" 
CustomStreamType :: struct {
	base : PCMStreamType,
	t_EncodingAlgorithm : InputAlgorithmType,
	t_DecodingAlgorithm : InputOutputAlgorithmType,
	t_encodedStreamRef : NameReferenceType,
	t_decodedStreamRef : NameReferenceType,

}

MATH_ALGORITHM_TYPE :: "MathAlgorithmType" 
MathAlgorithmType :: struct {
	base : NameDescriptionType,
	t_MathOperation : TriggeredMathOperationType,

}

ARGUMENT_INSTANCE_REF_TYPE :: "ArgumentInstanceRefType" 
ArgumentInstanceRefType :: struct {
	t_argumentRef : NameType,
	t_useCalibratedValue : xs_boolean,

}

RELATIVE_TIME_ARGUMENT_TYPE :: "RelativeTimeArgumentType" 
RelativeTimeArgumentType :: struct {
	base : ArgumentRelativeTimeDataType,

}

PARAMETER_PROPERTIES_TYPE :: "ParameterPropertiesType" 
ParameterPropertiesType :: struct {
	t_SystemName : xs_string,
	t_ValidityCondition : MatchCriteriaType,
	t_PhysicalAddressSet : PhysicalAddressSetType,
	t_TimeAssociation : TimeAssociationType,
	t_dataSource : TelemetryDataSourceType,
	t_readOnly : xs_boolean,
	t_persistence : xs_boolean,

}

QUEUED_VERIFIER_TYPE :: "QueuedVerifierType" 
QueuedVerifierType :: struct {
	base : CommandVerifierType,

}

DISCRETE_LOOKUP_LIST_TYPE :: "DiscreteLookupListType" 
DiscreteLookupListType :: struct {
	t_DiscreteLookup : [dynamic]DiscreteLookupType,

}

O_RED_CONDITIONS_TYPE :: "ORedConditionsType" 
ORedConditionsType :: struct {
	base : BaseConditionsType,
	t_choice_0 : [2][dynamic]t_ORedConditionsType0,

}

t_ORedConditionsType0:: union {
	ANDedConditionsType,
	ComparisonCheckType,
}

BASE_META_COMMAND_TYPE :: "BaseMetaCommandType" 
BaseMetaCommandType :: struct {
	t_ArgumentAssignmentList : ArgumentAssignmentListType,
	t_metaCommandRef : NameReferenceType,

}

BASIS_TYPE :: "BasisType" 
BasisType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_BasisType_Enumeration := [?]string { "perSecond", "perContainerUpdate",  }

BINARY_CONTEXT_ALARM_LIST_TYPE :: "BinaryContextAlarmListType" 
BinaryContextAlarmListType :: struct {
	t_ContextAlarm : [dynamic]BinaryContextAlarmType,

}

INTEGER_PARAMETER_TYPE :: "IntegerParameterType" 
IntegerParameterType :: struct {
	base : IntegerDataType,
	t_DefaultAlarm : NumericAlarmType,
	t_ContextAlarmList : NumericContextAlarmListType,

}

RECEIVED_VERIFIER_TYPE :: "ReceivedVerifierType" 
ReceivedVerifierType :: struct {
	base : CommandVerifierType,

}

TRANSMISSION_CONSTRAINT_TYPE :: "TransmissionConstraintType" 
TransmissionConstraintType :: struct {
	base : MatchCriteriaType,
	t_timeOut : RelativeTimeType,
	t_suspendable : xs_boolean,

}

ARGUMENT_COMPARISON_CHECK_TYPE :: "ArgumentComparisonCheckType" 
ArgumentComparisonCheckType :: struct {
	base : BaseConditionsType,
	t_ComparisonOperator : ComparisonOperatorsType,
	t_choice_0 : t_ArgumentComparisonCheckType0,
	t_choice_1 : t_ArgumentComparisonCheckType1,

}

t_ArgumentComparisonCheckType0:: union {
	ArgumentInstanceRefType,
	ParameterInstanceRefType,
}

t_ArgumentComparisonCheckType1:: union {
	xs_string,
	t_ArgumentComparisonCheckType2,
}

t_ArgumentComparisonCheckType2:: union {
	ArgumentInstanceRefType,
	ParameterInstanceRefType,
}

BOOLEAN_ARGUMENT_TYPE :: "BooleanArgumentType" 
BooleanArgumentType :: struct {
	base : ArgumentBooleanDataType,

}

TRIGGER_SET_TYPE :: "TriggerSetType" 
TriggerSetType :: struct {
	t_name : xs_string,
	t_triggerRate : NonNegativeLongType,
	t_choice_0 : [dynamic]t_TriggerSetType0,

}

t_TriggerSetType0:: union {
	OnPeriodicRateTriggerType,
	OnContainerUpdateTriggerType,
	OnParameterUpdateTriggerType,
}

STREAM_SEGMENT_ENTRY_TYPE :: "StreamSegmentEntryType" 
StreamSegmentEntryType :: struct {
	base : SequenceEntryType,
	t_streamRef : NameReferenceType,
	t_order : PositiveLongType,
	t_sizeInBits : PositiveLongType,

}

BOOLEAN_CONTEXT_ALARM_TYPE :: "BooleanContextAlarmType" 
BooleanContextAlarmType :: struct {
	base : BooleanAlarmType,
	t_ContextMatch : ContextMatchType,

}

AUTHOR_SET_TYPE :: "AuthorSetType" 
AuthorSetType :: struct {
	t_Author : [dynamic]AuthorType,

}

ARGUMENT_BINARY_DATA_TYPE :: "ArgumentBinaryDataType" 
ArgumentBinaryDataType :: struct {
	base : ArgumentBaseDataType,
	t_initialValue : xs_hexBinary,

}

TRANSMISSION_CONSTRAINT_LIST_TYPE :: "TransmissionConstraintListType" 
TransmissionConstraintListType :: struct {
	t_TransmissionConstraint : [dynamic]TransmissionConstraintType,

}

CONTEXT_SIGNIFICANCE_LIST_TYPE :: "ContextSignificanceListType" 
ContextSignificanceListType :: struct {
	t_ContextSignificance : [dynamic]ContextSignificanceType,

}

CHANGE_BASIS_TYPE :: "ChangeBasisType" 
ChangeBasisType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_ChangeBasisType_Enumeration := [?]string { "absoluteChange", "percentageChange",  }

COMMAND_CONTAINER_ENTRY_LIST_TYPE :: "CommandContainerEntryListType" 
CommandContainerEntryListType :: struct {
	t_choice_0 : [dynamic]t_CommandContainerEntryListType0,

}

t_CommandContainerEntryListType0:: union {
	ArgumentFixedValueEntryType,
	ArgumentArrayArgumentRefEntryType,
	ArgumentArgumentRefEntryType,
	ArgumentArrayParameterRefEntryType,
	ArgumentIndirectParameterRefEntryType,
	ArgumentStreamSegmentEntryType,
	ArgumentContainerSegmentRefEntryType,
	ArgumentContainerRefEntryType,
	ArgumentParameterSegmentRefEntryType,
	ArgumentParameterRefEntryType,
}

FLAG_BIT_TYPE :: "FlagBitType" 
FlagBitType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_FlagBitType_Enumeration := [?]string { "zeros", "ones",  }

REFERENCE_TIME_TYPE :: "ReferenceTimeType" 
ReferenceTimeType :: struct {
	t_choice_0 : t_ReferenceTimeType0,

}

t_ReferenceTimeType0:: union {
	EpochType,
	ParameterInstanceRefType,
}

FIXED_FRAME_SYNC_STRATEGY_TYPE :: "FixedFrameSyncStrategyType" 
FixedFrameSyncStrategyType :: struct {
	base : SyncStrategyType,
	t_SyncPattern : SyncPatternType,

}

BOOLEAN_CONTEXT_ALARM_LIST_TYPE :: "BooleanContextAlarmListType" 
BooleanContextAlarmListType :: struct {
	t_ContextAlarm : [dynamic]BooleanContextAlarmType,

}

RESTRICTION_CRITERIA_TYPE :: "RestrictionCriteriaType" 
RestrictionCriteriaType :: struct {
	base : MatchCriteriaType,
	t_choice_0 : t_RestrictionCriteriaType0,

}

t_RestrictionCriteriaType0:: union {
	ContainerRefType,
}

META_COMMAND_SET_TYPE :: "MetaCommandSetType" 
MetaCommandSetType :: struct {
	t_choice_0 : [dynamic]t_MetaCommandSetType0,

}

t_MetaCommandSetType0:: union {
	BlockMetaCommandType,
	NameReferenceType,
	MetaCommandType,
}

PARAMETER_INSTANCE_REF_TYPE :: "ParameterInstanceRefType" 
ParameterInstanceRefType :: struct {
	base : ParameterRefType,
	t_instance : xs_long,
	t_useCalibratedValue : xs_boolean,

}

CONTAINER_REF_SET_TYPE :: "ContainerRefSetType" 
ContainerRefSetType :: struct {
	t_ContainerRef : [dynamic]ContainerRefType,

}

ARRAY_DATA_TYPE_TYPE :: "ArrayDataTypeType" 
ArrayDataTypeType :: struct {
	base : NameDescriptionType,
	t_arrayTypeRef : NameReferenceType,

}

ARGUMENT_DISCRETE_LOOKUP_TYPE :: "ArgumentDiscreteLookupType" 
ArgumentDiscreteLookupType :: struct {
	base : ArgumentMatchCriteriaType,
	t_value : xs_long,

}

ARGUMENT_PARAMETER_SEGMENT_REF_ENTRY_TYPE :: "ArgumentParameterSegmentRefEntryType" 
ArgumentParameterSegmentRefEntryType :: struct {
	base : ArgumentSequenceEntryType,
	t_parameterRef : NameReferenceType,
	t_order : PositiveLongType,
	t_sizeInBits : PositiveLongType,

}

INDIRECT_PARAMETER_REF_ENTRY_TYPE :: "IndirectParameterRefEntryType" 
IndirectParameterRefEntryType :: struct {
	base : SequenceEntryType,
	t_ParameterInstance : ParameterInstanceRefType,
	t_aliasNameSpace : xs_string,

}

ARGUMENT_RELATIVE_TIME_DATA_TYPE :: "ArgumentRelativeTimeDataType" 
ArgumentRelativeTimeDataType :: struct {
	base : ArgumentBaseTimeDataType,
	t_initialValue : xs_duration,

}

ARGUMENT_PARAMETER_REF_ENTRY_TYPE :: "ArgumentParameterRefEntryType" 
ArgumentParameterRefEntryType :: struct {
	base : ArgumentSequenceEntryType,
	t_parameterRef : NameReferenceType,

}

CONSEQUENCE_LEVEL_TYPE :: "ConsequenceLevelType" 
ConsequenceLevelType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_ConsequenceLevelType_Enumeration := [?]string { "normal", "vital", "critical", "forbidden", "user1", "user2",  }

LOCATION_IN_CONTAINER_IN_BITS_TYPE :: "LocationInContainerInBitsType" 
LocationInContainerInBitsType :: struct {
	base : IntegerValueType,
	t_referenceLocation : ReferenceLocationType,

}

ARGUMENT_REPEAT_TYPE :: "ArgumentRepeatType" 
ArgumentRepeatType :: struct {
	t_Count : ArgumentIntegerValueType,
	t_Offset : ArgumentIntegerValueType,

}

PARAMETER_VALUE_CHANGE_TYPE :: "ParameterValueChangeType" 
ParameterValueChangeType :: struct {
	t_ParameterRef : ParameterRefType,
	t_Change : ChangeValueType,

}

MULTI_RANGE_TYPE :: "MultiRangeType" 
MultiRangeType :: struct {
	base : FloatRangeType,
	t_rangeForm : RangeFormType,
	t_level : ConcernLevelsType,

}

RANGE_FORM_TYPE :: "RangeFormType" 
RangeFormType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_RangeFormType_Enumeration := [?]string { "outside", "inside",  }

BINARY_ARGUMENT_TYPE :: "BinaryArgumentType" 
BinaryArgumentType :: struct {
	base : ArgumentBinaryDataType,

}

VALID_RANGE :: "ValidRange" 
ValidRange :: struct {
	t_validRangeAppliesToCalibrated : xs_boolean,

}

CONCERN_LEVELS_TYPE :: "ConcernLevelsType" 
ConcernLevelsType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_ConcernLevelsType_Enumeration := [?]string { "normal", "watch", "warning", "distress", "critical", "severe",  }

VARIABLE_FRAME_STREAM_TYPE :: "VariableFrameStreamType" 
VariableFrameStreamType :: struct {
	base : FrameStreamType,
	t_SyncStrategy : VariableFrameSyncStrategyType,

}

ARGUMENT_CONTAINER_SEGMENT_REF_ENTRY_TYPE :: "ArgumentContainerSegmentRefEntryType" 
ArgumentContainerSegmentRefEntryType :: struct {
	base : ArgumentSequenceEntryType,
	t_containerRef : NameReferenceType,
	t_order : PositiveLongType,
	t_sizeInBits : PositiveLongType,

}

EPOCH_TIME_ENUMS_TYPE :: "EpochTimeEnumsType" 
EpochTimeEnumsType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_EpochTimeEnumsType_Enumeration := [?]string { "TAI", "J2000", "UNIX", "GPS",  }

ACCEPTED_VERIFIER_TYPE :: "AcceptedVerifierType" 
AcceptedVerifierType :: struct {
	base : CommandVerifierType,

}

ARGUMENT_DYNAMIC_VALUE_TYPE :: "ArgumentDynamicValueType" 
ArgumentDynamicValueType :: struct {
	t_LinearAdjustment : LinearAdjustmentType,
	t_choice_0 : t_ArgumentDynamicValueType0,

}

t_ArgumentDynamicValueType0:: union {
	ParameterInstanceRefType,
	ArgumentInstanceRefType,
}

ABSOLUTE_TIME_ARGUMENT_TYPE :: "AbsoluteTimeArgumentType" 
AbsoluteTimeArgumentType :: struct {
	base : ArgumentAbsoluteTimeDataType,

}

FLOATING_POINT_NOTATION_TYPE :: "FloatingPointNotationType" 
FloatingPointNotationType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_FloatingPointNotationType_Enumeration := [?]string { "normal", "scientific", "engineering",  }

COMMAND_VERIFIER_TYPE :: "CommandVerifierType" 
CommandVerifierType :: struct {
	base : OptionalNameDescriptionType,
	t_choice_0 : t_CommandVerifierType0,
	t_choice_1 : t_CommandVerifierType1,

}

t_CommandVerifierType0:: union {
	ComparisonType,
	BooleanExpressionType,
	InputAlgorithmType,
	ParameterValueChangeType,
	ContainerRefType,
	ComparisonListType,
}

t_CommandVerifierType1:: union {
	CheckWindowAlgorithmsType,
	CheckWindowType,
}

INTEGER_DATA_TYPE :: "IntegerDataType" 
IntegerDataType :: struct {
	base : BaseDataType,
	t_ToString : ToStringType,
	t_initialValue : xs_long,
	t_sizeInBits : PositiveLongType,
	t_signed : xs_boolean,
	t_ValidRange : ValidRange,

}

ARGUMENT_BINARY_DATA_ENCODING_TYPE :: "ArgumentBinaryDataEncodingType" 
ArgumentBinaryDataEncodingType :: struct {
	base : DataEncodingType,
	t_SizeInBits : ArgumentIntegerValueType,
	t_FromBinaryTransformAlgorithm : ArgumentInputAlgorithmType,
	t_ToBinaryTransformAlgorithm : ArgumentInputAlgorithmType,

}

STRING_ENCODING_TYPE :: "StringEncodingType" 
StringEncodingType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_StringEncodingType_Enumeration := [?]string { "US-ASCII", "ISO-8859-1", "Windows-1252", "UTF-8", "UTF-16", "UTF-16LE", "UTF-16BE", "UTF-32", "UTF-32LE", "UTF-32BE",  }

RATE_IN_STREAM_SET_TYPE :: "RateInStreamSetType" 
RateInStreamSetType :: struct {
	t_RateInStream : [dynamic]RateInStreamWithStreamNameType,

}

DESCRIPTION_TYPE :: "DescriptionType" 
DescriptionType :: struct {
	t_LongDescription : LongDescriptionType,
	t_AliasSet : AliasSetType,
	t_AncillaryDataSet : AncillaryDataSetType,
	t_shortDescription : ShortDescriptionType,

}

NOTE_TYPE :: "NoteType" 
NoteType :: struct {
	t_restriction : xs_string,

}

COMPARISON_CHECK_TYPE :: "ComparisonCheckType" 
ComparisonCheckType :: struct {
	base : BaseConditionsType,
	t_ParameterInstanceRef : ParameterInstanceRefType,
	t_ComparisonOperator : ComparisonOperatorsType,
	t_choice_0 : t_ComparisonCheckType0,

}

t_ComparisonCheckType0:: union {
	xs_string,
	ParameterInstanceRefType,
}

ARGUMENT_TYPE :: "ArgumentType" 
ArgumentType :: struct {
	base : NameDescriptionType,
	t_argumentTypeRef : NameReferenceType,
	t_initialValue : xs_string,

}

DIMENSION_LIST_TYPE :: "DimensionListType" 
DimensionListType :: struct {
	t_Dimension : [dynamic]DimensionType,

}

AGGREGATE_ARGUMENT_TYPE :: "AggregateArgumentType" 
AggregateArgumentType :: struct {
	base : AggregateDataType,

}

BASE_TRIGGER_TYPE :: "BaseTriggerType" 
BaseTriggerType :: struct {

}

COMPARISON_TYPE :: "ComparisonType" 
ComparisonType :: struct {
	base : ParameterInstanceRefType,
	t_comparisonOperator : ComparisonOperatorsType,
	t_value : xs_string,

}

PARAMETER_REF_ENTRY_TYPE :: "ParameterRefEntryType" 
ParameterRefEntryType :: struct {
	base : SequenceEntryType,
	t_parameterRef : NameReferenceType,

}

CHECK_WINDOW_ALGORITHMS_TYPE :: "CheckWindowAlgorithmsType" 
CheckWindowAlgorithmsType :: struct {
	t_StartCheck : InputAlgorithmType,
	t_StopTime : InputAlgorithmType,

}

ALARM_TYPE :: "AlarmType" 
AlarmType :: struct {
	base : BaseAlarmType,
	t_minViolations : PositiveLongType,
	t_minConformance : PositiveLongType,
	t_choice_0 : t_AlarmType0,

}

t_AlarmType0:: union {
	CustomAlarmType,
	AlarmConditionsType,
}

ANCILLARY_DATA_TYPE :: "AncillaryDataType" 
AncillaryDataType :: struct {
	base : string,
	t_name : xs_string,
	t_mimeType : xs_string,
	t_href : xs_anyURI,

}

VALID_INTEGER_RANGE_SET_TYPE :: "ValidIntegerRangeSetType" 
ValidIntegerRangeSetType :: struct {
	t_ValidRange : [dynamic]IntegerRangeType,
	t_validRangeAppliesToCalibrated : xs_boolean,

}

ARGUMENT_INDIRECT_PARAMETER_REF_ENTRY_TYPE :: "ArgumentIndirectParameterRefEntryType" 
ArgumentIndirectParameterRefEntryType :: struct {
	base : ArgumentSequenceEntryType,
	t_ParameterInstance : ParameterInstanceRefType,
	t_aliasNameSpace : xs_string,

}

HISTORY_SET_TYPE :: "HistorySetType" 
HistorySetType :: struct {
	t_History : [dynamic]HistoryType,

}

BOOLEAN_EXPRESSION_TYPE :: "BooleanExpressionType" 
BooleanExpressionType :: struct {
	t_choice_0 : t_BooleanExpressionType0,

}

t_BooleanExpressionType0:: union {
	ORedConditionsType,
	ANDedConditionsType,
	ComparisonCheckType,
}

TIME_CONTEXT_ALARM_TYPE :: "TimeContextAlarmType" 
TimeContextAlarmType :: struct {
	base : TimeAlarmType,
	t_ContextMatch : ContextMatchType,

}

REPEAT_TYPE :: "RepeatType" 
RepeatType :: struct {
	t_Count : IntegerValueType,
	t_Offset : IntegerValueType,

}

CONTEXT_SIGNIFICANCE_TYPE :: "ContextSignificanceType" 
ContextSignificanceType :: struct {
	t_ContextMatch : ContextMatchType,
	t_Significance : SignificanceType,

}

INPUT_PARAMETER_INSTANCE_REF_TYPE :: "InputParameterInstanceRefType" 
InputParameterInstanceRefType :: struct {
	base : ParameterInstanceRefType,
	t_inputName : xs_string,

}

SIMPLE_ALGORITHM_TYPE :: "SimpleAlgorithmType" 
SimpleAlgorithmType :: struct {
	base : NameDescriptionType,
	t_AlgorithmText : AlgorithmTextType,
	t_ExternalAlgorithmSet : ExternalAlgorithmSetType,

}

ARGUMENT_COMPARISON_LIST_TYPE :: "ArgumentComparisonListType" 
ArgumentComparisonListType :: struct {
	t_Comparison : [dynamic]ArgumentComparisonType,

}

NAME_DESCRIPTION_TYPE :: "NameDescriptionType" 
NameDescriptionType :: struct {
	base : DescriptionType,
	t_name : NameType,

}

DISCRETE_LOOKUP_TYPE :: "DiscreteLookupType" 
DiscreteLookupType :: struct {
	base : MatchCriteriaType,
	t_value : xs_long,

}

HISTORY_TYPE :: "HistoryType" 
HistoryType :: struct {
	t_restriction : xs_string,

}

ENUMERATION_ALARM_LEVEL_TYPE :: "EnumerationAlarmLevelType" 
EnumerationAlarmLevelType :: struct {
	t_alarmLevel : ConcernLevelsType,
	t_enumerationLabel : xs_string,

}

TO_STRING_TYPE :: "ToStringType" 
ToStringType :: struct {
	t_NumberFormat : NumberFormatType,

}

ARGUMENT_SEQUENCE_ENTRY_TYPE :: "ArgumentSequenceEntryType" 
ArgumentSequenceEntryType :: struct {
	t_LocationInContainerInBits : ArgumentLocationInContainerInBitsType,
	t_RepeatEntry : ArgumentRepeatType,
	t_IncludeCondition : ArgumentMatchCriteriaType,
	t_AncillaryDataSet : AncillaryDataSetType,
	t_shortDescription : ShortDescriptionType,

}

ENUMERATION_LIST_TYPE :: "EnumerationListType" 
EnumerationListType :: struct {
	t_Enumeration : [dynamic]ValueEnumerationType,

}

ABSOLUTE_TIME_DATA_TYPE :: "AbsoluteTimeDataType" 
AbsoluteTimeDataType :: struct {
	base : BaseTimeDataType,
	t_initialValue : xs_dateTime,

}

ARGUMENT_INTEGER_DATA_TYPE :: "ArgumentIntegerDataType" 
ArgumentIntegerDataType :: struct {
	base : ArgumentBaseDataType,
	t_ToString : ToStringType,
	t_initialValue : FixedIntegerValueType,
	t_sizeInBits : PositiveLongType,
	t_signed : xs_boolean,

}

FRAME_STREAM_TYPE :: "FrameStreamType" 
FrameStreamType :: struct {
	base : PCMStreamType,
	t_StreamRef : StreamRefType,
	t_choice_0 : t_FrameStreamType0,

}

t_FrameStreamType0:: union {
	ServiceRefType,
	ContainerRefType,
}

TERM_TYPE :: "TermType" 
TermType :: struct {
	t_coefficient : xs_double,
	t_exponent : NonNegativeLongType,

}

ARGUMENT_LOCATION_IN_CONTAINER_IN_BITS_TYPE :: "ArgumentLocationInContainerInBitsType" 
ArgumentLocationInContainerInBitsType :: struct {
	base : ArgumentIntegerValueType,
	t_referenceLocation : ReferenceLocationType,

}

ARGUMENT_STREAM_SEGMENT_ENTRY_TYPE :: "ArgumentStreamSegmentEntryType" 
ArgumentStreamSegmentEntryType :: struct {
	base : ArgumentSequenceEntryType,
	t_streamRef : NameReferenceType,
	t_order : PositiveLongType,
	t_sizeInBits : PositiveLongType,

}

C_R_C_TYPE :: "CRCType" 
CRCType :: struct {
	t_Polynomial : xs_hexBinary,
	t_InitRemainder : xs_hexBinary,
	t_FinalXOR : xs_hexBinary,
	t_width : PositiveLongType,
	t_reflectData : xs_boolean,
	t_reflectRemainder : xs_boolean,
	t_bitsFromReference : NonNegativeLongType,
	t_reference : ReferencePointType,

}

META_COMMAND_STEP_TYPE :: "MetaCommandStepType" 
MetaCommandStepType :: struct {
	t_ArgumentAssigmentList : ArgumentAssignmentListType,
	t_metaCommandRef : NameReferenceType,

}

ENUMERATION_CONTEXT_ALARM_LIST_TYPE :: "EnumerationContextAlarmListType" 
EnumerationContextAlarmListType :: struct {
	t_ContextAlarm : [dynamic]EnumerationContextAlarmType,

}

UNIT_SET_TYPE :: "UnitSetType" 
UnitSetType :: struct {
	t_Unit : [dynamic]UnitType,

}

HEXADECIMAL_TYPE :: "HexadecimalType" 
HexadecimalType :: struct {
	t_restriction : xs_string,

}

CHANGE_VALUE_TYPE :: "ChangeValueType" 
ChangeValueType :: struct {
	t_value : xs_double,

}

CALIBRATOR_TYPE :: "CalibratorType" 
CalibratorType :: struct {
	base : BaseCalibratorType,
	t_choice_0 : t_CalibratorType0,

}

t_CalibratorType0:: union {
	MathOperationCalibratorType,
	PolynomialCalibratorType,
	SplineCalibratorType,
}

TIME_CONTEXT_ALARM_LIST_TYPE :: "TimeContextAlarmListType" 
TimeContextAlarmListType :: struct {
	t_ContextAlarm : [dynamic]TimeContextAlarmType,

}

ARRAY_PARAMETER_REF_ENTRY_TYPE :: "ArrayParameterRefEntryType" 
ArrayParameterRefEntryType :: struct {
	base : SequenceEntryType,
	t_DimensionList : DimensionListType,
	t_parameterRef : NameReferenceType,

}

INTEGER_ENCODING_TYPE :: "IntegerEncodingType" 
IntegerEncodingType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_IntegerEncodingType_Enumeration := [?]string { "unsigned", "signMagnitude", "twosComplement", "onesComplement", "BCD", "packedBCD",  }

CONTAINER_REF_TYPE :: "ContainerRefType" 
ContainerRefType :: struct {
	t_containerRef : NameReferenceType,

}

TIME_ALARM_TYPE :: "TimeAlarmType" 
TimeAlarmType :: struct {
	base : AlarmType,
	t_StaticAlarmRanges : TimeAlarmRangesType,
	t_ChangePerSecondAlarmRanges : TimeAlarmRangesType,

}

INTEGER_RANGE_TYPE :: "IntegerRangeType" 
IntegerRangeType :: struct {
	t_minInclusive : xs_long,
	t_maxInclusive : xs_long,

}

A_N_DED_CONDITIONS_TYPE :: "ANDedConditionsType" 
ANDedConditionsType :: struct {
	base : BaseConditionsType,
	t_choice_0 : [2][dynamic]t_ANDedConditionsType0,

}

t_ANDedConditionsType0:: union {
	ORedConditionsType,
	ComparisonCheckType,
}

NUMBER_FORMAT_TYPE :: "NumberFormatType" 
NumberFormatType :: struct {
	t_numberBase : RadixType,
	t_minimumFractionDigits : NonNegativeLongType,
	t_maximumFractionDigits : NonNegativeLongType,
	t_minimumIntegerDigits : NonNegativeLongType,
	t_maximumIntegerDigits : NonNegativeLongType,
	t_negativeSuffix : xs_string,
	t_positiveSuffix : xs_string,
	t_negativePrefix : xs_string,
	t_positivePrefix : xs_string,
	t_showThousandsGrouping : xs_boolean,
	t_notation : FloatingPointNotationType,

}

VARIABLE_FRAME_SYNC_STRATEGY_TYPE :: "VariableFrameSyncStrategyType" 
VariableFrameSyncStrategyType :: struct {
	base : SyncStrategyType,
	t_Flag : FlagType,

}

ENUMERATION_ALARM_LIST_TYPE :: "EnumerationAlarmListType" 
EnumerationAlarmListType :: struct {
	t_EnumerationAlarm : [dynamic]EnumerationAlarmLevelType,

}

LEADING_SIZE_TYPE :: "LeadingSizeType" 
LeadingSizeType :: struct {
	t_sizeInBitsOfSizeTag : PositiveLongType,

}

FAILED_VERIFIER_TYPE :: "FailedVerifierType" 
FailedVerifierType :: struct {
	base : CommandVerifierType,
	t_ReturnParmRef : ParameterRefType,

}

ARGUMENT_ABSOLUTE_TIME_DATA_TYPE :: "ArgumentAbsoluteTimeDataType" 
ArgumentAbsoluteTimeDataType :: struct {
	base : ArgumentBaseTimeDataType,
	t_initialValue : xs_dateTime,

}

ARGUMENT_MATCH_CRITERIA_TYPE :: "ArgumentMatchCriteriaType" 
ArgumentMatchCriteriaType :: struct {
	t_choice_0 : t_ArgumentMatchCriteriaType0,

}

t_ArgumentMatchCriteriaType0:: union {
	ArgumentInputAlgorithmType,
	ArgumentBooleanExpressionType,
	ArgumentComparisonListType,
	ArgumentComparisonType,
}

FIXED_FRAME_STREAM_TYPE :: "FixedFrameStreamType" 
FixedFrameStreamType :: struct {
	base : FrameStreamType,
	t_SyncStrategy : FixedFrameSyncStrategyType,
	t_syncApertureInBits : NonNegativeLongType,
	t_frameLengthInBits : xs_long,

}

ENUMERATION_CONTEXT_ALARM_TYPE :: "EnumerationContextAlarmType" 
EnumerationContextAlarmType :: struct {
	base : EnumerationAlarmType,
	t_ContextMatch : ContextMatchType,

}

ARGUMENT_CONTAINER_REF_ENTRY_TYPE :: "ArgumentContainerRefEntryType" 
ArgumentContainerRefEntryType :: struct {
	base : ArgumentSequenceEntryType,
	t_containerRef : NameReferenceType,

}

ERROR_DETECT_CORRECT_TYPE :: "ErrorDetectCorrectType" 
ErrorDetectCorrectType :: struct {
	t_choice_0 : t_ErrorDetectCorrectType0,

}

t_ErrorDetectCorrectType0:: union {
	ParityType,
	CRCType,
	ChecksumType,
}

PARITY_TYPE :: "ParityType" 
ParityType :: struct {
	t_type : ParityFormType,
	t_bitsFromReference : NonNegativeLongType,
	t_reference : ReferencePointType,

}

REFERENCE_LOCATION_TYPE :: "ReferenceLocationType" 
ReferenceLocationType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_ReferenceLocationType_Enumeration := [?]string { "containerStart", "containerEnd", "previousEntry", "nextEntry",  }

MESSAGE_TYPE :: "MessageType" 
MessageType :: struct {
	base : NameDescriptionType,
	t_MatchCriteria : MatchCriteriaType,
	t_ContainerRef : ContainerRefType,

}

ABSOLUTE_TIME_PARAMETER_TYPE :: "AbsoluteTimeParameterType" 
AbsoluteTimeParameterType :: struct {
	base : AbsoluteTimeDataType,

}

TELEMETRY_DATA_SOURCE_TYPE :: "TelemetryDataSourceType" 
TelemetryDataSourceType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_TelemetryDataSourceType_Enumeration := [?]string { "telemetered", "derived", "constant", "local", "ground",  }

TRANSFERRED_TO_RANGE_VERIFIER_TYPE :: "TransferredToRangeVerifierType" 
TransferredToRangeVerifierType :: struct {
	base : CommandVerifierType,

}

BINARY_TYPE :: "BinaryType" 
BinaryType :: struct {
	t_restriction : xs_string,

}

CUSTOM_ALARM_TYPE :: "CustomAlarmType" 
CustomAlarmType :: struct {
	base : BaseAlarmType,
	t_InputAlgorithm : InputAlgorithmType,

}

BYTE_ORDER_ARBITRARY_TYPE :: "ByteOrderArbitraryType" 
ByteOrderArbitraryType :: struct {
	t_restriction : xs_string,

}

INTEGER_VALUE_TYPE :: "IntegerValueType" 
IntegerValueType :: struct {
	t_choice_0 : t_IntegerValueType0,

}

t_IntegerValueType0:: union {
	DiscreteLookupListType,
	DynamicValueType,
	xs_long,
}

SEQUENCE_CONTAINER_TYPE :: "SequenceContainerType" 
SequenceContainerType :: struct {
	base : ContainerType,
	t_EntryList : EntryListType,
	t_BaseContainer : BaseContainerType,
	t_abstract : xs_boolean,
	t_idlePattern : FixedIntegerValueType,

}

INTEGER_DATA_ENCODING_TYPE :: "IntegerDataEncodingType" 
IntegerDataEncodingType :: struct {
	base : DataEncodingType,
	t_DefaultCalibrator : CalibratorType,
	t_ContextCalibratorList : ContextCalibratorListType,
	t_encoding : IntegerEncodingType,
	t_sizeInBits : PositiveLongType,
	t_changeThreshold : NonNegativeLongType,

}

VALIDATION_STATUS_TYPE :: "ValidationStatusType" 
ValidationStatusType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_ValidationStatusType_Enumeration := [?]string { "Unknown", "Working", "Draft", "Test", "Validated", "Released", "Withdrawn",  }

STRING_ALARM_TYPE :: "StringAlarmType" 
StringAlarmType :: struct {
	base : AlarmType,
	t_StringAlarmList : StringAlarmListType,
	t_defaultAlarmLevel : ConcernLevelsType,

}

NUMERIC_CONTEXT_ALARM_LIST_TYPE :: "NumericContextAlarmListType" 
NumericContextAlarmListType :: struct {
	t_ContextAlarm : [dynamic]NumericContextAlarmType,

}

DIMENSION_TYPE :: "DimensionType" 
DimensionType :: struct {
	t_StartingIndex : IntegerValueType,
	t_EndingIndex : IntegerValueType,

}

FLOAT_ARGUMENT_TYPE :: "FloatArgumentType" 
FloatArgumentType :: struct {
	base : ArgumentFloatDataType,
	t_ValidRangeSet : ValidFloatRangeSetType,

}

NAME_REFERENCE_TYPE :: "NameReferenceType" 
NameReferenceType :: struct {
	t_restriction : xs_normalizedString,

}

COMPLETE_VERIFIER_TYPE :: "CompleteVerifierType" 
CompleteVerifierType :: struct {
	base : CommandVerifierType,
	t_ReturnParmRef : ParameterRefType,

}

CHANGE_SPAN_TYPE :: "ChangeSpanType" 
ChangeSpanType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_ChangeSpanType_Enumeration := [?]string { "changePerSecond", "changePerSample",  }

TIME_UNITS_TYPE :: "TimeUnitsType" 
TimeUnitsType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_TimeUnitsType_Enumeration := [?]string { "seconds", "picoSeconds", "days", "months", "years",  }

SPLINE_POINT_TYPE :: "SplinePointType" 
SplinePointType :: struct {
	t_order : NonNegativeLongType,
	t_raw : xs_double,
	t_calibrated : xs_double,

}

BLOCK_META_COMMAND_TYPE :: "BlockMetaCommandType" 
BlockMetaCommandType :: struct {
	base : NameDescriptionType,
	t_MetaCommandStepList : MetaCommandStepListType,

}

ARGUMENT_DIMENSION_LIST_TYPE :: "ArgumentDimensionListType" 
ArgumentDimensionListType :: struct {
	t_Dimension : [dynamic]ArgumentDimensionType,

}

PARAMETER_REF_TYPE :: "ParameterRefType" 
ParameterRefType :: struct {
	t_parameterRef : NameReferenceType,

}

AGGREGATE_PARAMETER_TYPE :: "AggregateParameterType" 
AggregateParameterType :: struct {
	base : AggregateDataType,

}

MESSAGE_REF_TYPE :: "MessageRefType" 
MessageRefType :: struct {
	t_messageRef : NameReferenceType,

}

STRING_ARGUMENT_TYPE :: "StringArgumentType" 
StringArgumentType :: struct {
	base : ArgumentStringDataType,

}

SEQUENCE_ENTRY_TYPE :: "SequenceEntryType" 
SequenceEntryType :: struct {
	t_LocationInContainerInBits : LocationInContainerInBitsType,
	t_RepeatEntry : RepeatType,
	t_IncludeCondition : MatchCriteriaType,
	t_TimeAssociation : TimeAssociationType,
	t_AncillaryDataSet : AncillaryDataSetType,
	t_shortDescription : ShortDescriptionType,

}

RELATIVE_TIME_PARAMETER_TYPE :: "RelativeTimeParameterType" 
RelativeTimeParameterType :: struct {
	base : RelativeTimeDataType,
	t_DefaultAlarm : TimeAlarmType,
	t_ContextAlarmList : TimeContextAlarmListType,

}

ALARM_RANGES_TYPE :: "AlarmRangesType" 
AlarmRangesType :: struct {
	base : BaseAlarmType,
	t_WatchRange : FloatRangeType,
	t_WarningRange : FloatRangeType,
	t_DistressRange : FloatRangeType,
	t_CriticalRange : FloatRangeType,
	t_SevereRange : FloatRangeType,
	t_rangeForm : RangeFormType,

}

MATH_OPERATORS_TYPE :: "MathOperatorsType" 
MathOperatorsType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_MathOperatorsType_Enumeration := [?]string { "+", "-", "*", "/", "%", "^", "y^x", "ln", "log", "e^x", "1/x", "x!", "tan", "cos", "sin", "atan", "atan2", "acos", "asin", "tanh", "cosh", "sinh", "atanh", "acosh", "asinh", "swap", "drop", "dup", "over", "<<", ">>", "&", "|", "&&", "||", "!", "abs", "div", "int", ">", ">=", "<", "<=", "==", "!=", "min", "max", "xor", "~",  }

ARGUMENT_FIXED_VALUE_ENTRY_TYPE :: "ArgumentFixedValueEntryType" 
ArgumentFixedValueEntryType :: struct {
	base : ArgumentSequenceEntryType,
	t_name : xs_string,
	t_binaryValue : xs_hexBinary,
	t_sizeInBits : PositiveLongType,

}

STREAM_REF_TYPE :: "StreamRefType" 
StreamRefType :: struct {
	t_streamRef : NameReferenceType,

}

BINARY_ALARM_TYPE :: "BinaryAlarmType" 
BinaryAlarmType :: struct {
	base : AlarmType,

}

INTERLOCK_TYPE :: "InterlockType" 
InterlockType :: struct {
	t_scopeToSpaceSystem : NameReferenceType,
	t_verificationToWaitFor : VerifierEnumerationType,
	t_verificationProgressPercentage : xs_double,
	t_suspendable : xs_boolean,

}

CHANGE_ALARM_RANGES_TYPE :: "ChangeAlarmRangesType" 
ChangeAlarmRangesType :: struct {
	base : AlarmRangesType,
	t_changeType : ChangeSpanType,
	t_changeBasis : ChangeBasisType,
	t_spanOfInterestInSamples : PositiveLongType,
	t_spanOfInterestInSeconds : xs_double,

}

ALIAS_TYPE :: "AliasType" 
AliasType :: struct {
	t_nameSpace : xs_string,
	t_alias : xs_string,

}

NOTE_SET_TYPE :: "NoteSetType" 
NoteSetType :: struct {
	t_Note : [dynamic]NoteType,

}

COMMAND_CONTAINER_TYPE :: "CommandContainerType" 
CommandContainerType :: struct {
	base : ContainerType,
	t_EntryList : CommandContainerEntryListType,
	t_BaseContainer : BaseContainerType,

}

SPACE_SYSTEM_TYPE :: "SpaceSystemType" 
SpaceSystemType :: struct {
	base : NameDescriptionType,
	t_Header : HeaderType,
	t_TelemetryMetaData : TelemetryMetaDataType,
	t_CommandMetaData : CommandMetaDataType,
	t_ServiceSet : ServiceSetType,
	t_operationalStatus : xs_token,

}

FLOAT_DATA_ENCODING_TYPE :: "FloatDataEncodingType" 
FloatDataEncodingType :: struct {
	base : DataEncodingType,
	t_DefaultCalibrator : CalibratorType,
	t_ContextCalibratorList : ContextCalibratorListType,
	t_encoding : FloatEncodingType,
	t_sizeInBits : FloatEncodingSizeInBitsType,
	t_changeThreshold : xs_double,

}

ARGUMENT_INTEGER_VALUE_TYPE :: "ArgumentIntegerValueType" 
ArgumentIntegerValueType :: struct {
	t_choice_0 : t_ArgumentIntegerValueType0,

}

t_ArgumentIntegerValueType0:: union {
	ArgumentDiscreteLookupListType,
	ArgumentDynamicValueType,
	xs_long,
}

PHYSICAL_ADDRESS_TYPE :: "PhysicalAddressType" 
PhysicalAddressType :: struct {
	t_SubAddress : ^PhysicalAddressType,
	t_sourceName : xs_string,
	t_sourceAddress : xs_string,

}

META_COMMAND_STEP_LIST_TYPE :: "MetaCommandStepListType" 
MetaCommandStepListType :: struct {
	t_MetaCommandStep : [dynamic]MetaCommandStepType,

}

CONTAINER_SEGMENT_REF_ENTRY_TYPE :: "ContainerSegmentRefEntryType" 
ContainerSegmentRefEntryType :: struct {
	base : SequenceEntryType,
	t_containerRef : NameReferenceType,
	t_order : PositiveLongType,
	t_sizeInBits : PositiveLongType,

}

STRING_PARAMETER_TYPE :: "StringParameterType" 
StringParameterType :: struct {
	base : StringDataType,
	t_DefaultAlarm : StringAlarmType,
	t_ContextAlarmList : StringContextAlarmListType,

}

P_C_M_TYPE :: "PCMType" 
PCMType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_PCMType_Enumeration := [?]string { "NRZL", "NRZM", "NRZS", "BiPhaseL", "BiPhaseM", "BiPhaseS",  }

MEMBER_LIST_TYPE :: "MemberListType" 
MemberListType :: struct {
	t_Member : [dynamic]MemberType,

}

INTEGER_ARGUMENT_TYPE :: "IntegerArgumentType" 
IntegerArgumentType :: struct {
	base : ArgumentIntegerDataType,
	t_ValidRangeSet : ValidIntegerRangeSetType,

}

BINARY_CONTEXT_ALARM_TYPE :: "BinaryContextAlarmType" 
BinaryContextAlarmType :: struct {
	base : AlarmType,
	t_ContextMatch : ContextMatchType,

}

COMMAND_CONTAINER_SET_TYPE :: "CommandContainerSetType" 
CommandContainerSetType :: struct {
	t_CommandContainer : [dynamic]SequenceContainerType,

}

PARAMETER_TYPE :: "ParameterType" 
ParameterType :: struct {
	base : NameDescriptionType,
	t_ParameterProperties : ParameterPropertiesType,
	t_parameterTypeRef : NameReferenceType,
	t_initialValue : xs_string,

}

ARGUMENT_DISCRETE_LOOKUP_LIST_TYPE :: "ArgumentDiscreteLookupListType" 
ArgumentDiscreteLookupListType :: struct {
	t_DiscreteLookup : [dynamic]ArgumentDiscreteLookupType,

}

AUTO_INVERT_TYPE :: "AutoInvertType" 
AutoInvertType :: struct {
	t_InvertAlgorithm : InputAlgorithmType,
	t_badFramesToAutoInvert : PositiveLongType,

}

BASE_TIME_DATA_TYPE :: "BaseTimeDataType" 
BaseTimeDataType :: struct {
	base : NameDescriptionType,
	t_Encoding : EncodingType,
	t_ReferenceTime : ReferenceTimeType,
	t_baseType : NameReferenceType,

}

EXECUTION_VERIFIER_TYPE :: "ExecutionVerifierType" 
ExecutionVerifierType :: struct {
	base : CommandVerifierType,
	t_PercentComplete : PercentCompleteType,

}

BOOLEAN_PARAMETER_TYPE :: "BooleanParameterType" 
BooleanParameterType :: struct {
	base : BooleanDataType,
	t_DefaultAlarm : BooleanAlarmType,
	t_ContextAlarmList : BooleanContextAlarmListType,

}

VARIABLE_STRING_TYPE :: "VariableStringType" 
VariableStringType :: struct {
	t_LeadingSize : LeadingSizeType,
	t_TerminationChar : xs_hexBinary,
	t_maxSizeInBits : PositiveLongType,
	t_choice_0 : t_VariableStringType0,

}

t_VariableStringType0:: union {
	DiscreteLookupListType,
	DynamicValueType,
}

ARGUMENT_INPUT_SET_TYPE :: "ArgumentInputSetType" 
ArgumentInputSetType :: struct {
	t_choice_0 : [dynamic]t_ArgumentInputSetType0,

}

t_ArgumentInputSetType0:: union {
	ArgumentInstanceRefType,
	InputParameterInstanceRefType,
}

ARGUMENT_BOOLEAN_EXPRESSION_TYPE :: "ArgumentBooleanExpressionType" 
ArgumentBooleanExpressionType :: struct {
	t_choice_0 : t_ArgumentBooleanExpressionType0,

}

t_ArgumentBooleanExpressionType0:: union {
	ArgumentORedConditionsType,
	ArgumentANDedConditionsType,
	ArgumentComparisonCheckType,
}

ALGORITHM_TEXT_TYPE :: "AlgorithmTextType" 
AlgorithmTextType :: struct {
	base : string,
	t_language : xs_string,

}

SPLINE_CALIBRATOR_TYPE :: "SplineCalibratorType" 
SplineCalibratorType :: struct {
	base : BaseCalibratorType,
	t_SplinePoint : [dynamic]SplinePointType,
	t_order : NonNegativeLongType,
	t_extrapolate : xs_boolean,

}

TIME_ASSOCIATION_UNIT_TYPE :: "TimeAssociationUnitType" 
TimeAssociationUnitType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_TimeAssociationUnitType_Enumeration := [?]string { "si_nanosecond", "si_microsecond", "si_millsecond", "si_second", "minute", "day", "julianYear",  }

ENUMERATION_ALARM_TYPE :: "EnumerationAlarmType" 
EnumerationAlarmType :: struct {
	base : AlarmType,
	t_EnumerationAlarmList : EnumerationAlarmListType,
	t_defaultAlarmLevel : ConcernLevelsType,

}

ENTRY_LIST_TYPE :: "EntryListType" 
EntryListType :: struct {
	t_choice_0 : [dynamic]t_EntryListType0,

}

t_EntryListType0:: union {
	ArrayParameterRefEntryType,
	IndirectParameterRefEntryType,
	StreamSegmentEntryType,
	ContainerSegmentRefEntryType,
	ContainerRefEntryType,
	ParameterSegmentRefEntryType,
	ParameterRefEntryType,
}

DYNAMIC_VALUE_TYPE :: "DynamicValueType" 
DynamicValueType :: struct {
	t_ParameterInstanceRef : ParameterInstanceRefType,
	t_LinearAdjustment : LinearAdjustmentType,

}

P_C_M_STREAM_TYPE :: "PCMStreamType" 
PCMStreamType :: struct {
	base : NameDescriptionType,
	t_bitRateInBPS : xs_double,
	t_pcmType : PCMType,
	t_inverted : xs_boolean,

}

ENCODING_TYPE :: "EncodingType" 
EncodingType :: struct {
	t_units : TimeUnitsType,
	t_scale : xs_double,
	t_offset : xs_double,
	t_choice_0 : t_EncodingType0,

}

t_EncodingType0:: union {
	StringDataEncodingType,
	IntegerDataEncodingType,
	FloatDataEncodingType,
	BinaryDataEncodingType,
}

BINARY_PARAMETER_TYPE :: "BinaryParameterType" 
BinaryParameterType :: struct {
	base : BinaryDataType,
	t_DefaultAlarm : BinaryAlarmType,
	t_BinaryContextAlarmList : BinaryContextAlarmListType,

}

STRING_DATA_ENCODING_TYPE :: "StringDataEncodingType" 
StringDataEncodingType :: struct {
	base : DataEncodingType,
	t_encoding : StringEncodingType,
	t_choice_0 : t_StringDataEncodingType0,

}

t_StringDataEncodingType0:: union {
	VariableStringType,
	SizeInBitsType,
}

ALIAS_SET_TYPE :: "AliasSetType" 
AliasSetType :: struct {
	t_Alias : [dynamic]AliasType,

}

ARGUMENT_STRING_DATA_ENCODING_TYPE :: "ArgumentStringDataEncodingType" 
ArgumentStringDataEncodingType :: struct {
	base : DataEncodingType,
	t_encoding : StringEncodingType,
	t_choice_0 : t_ArgumentStringDataEncodingType0,

}

t_ArgumentStringDataEncodingType0:: union {
	ArgumentVariableStringType,
	SizeInBitsType,
}

ARGUMENT_ARRAY_PARAMETER_REF_ENTRY_TYPE :: "ArgumentArrayParameterRefEntryType" 
ArgumentArrayParameterRefEntryType :: struct {
	base : ArgumentSequenceEntryType,
	t_DimensionList : DimensionListType,
	t_parameterRef : NameReferenceType,
	t_lastEntryForThisArrayInstance : xs_boolean,

}

EPOCH_TYPE :: "EpochType" 
EpochType :: struct {
	t_enumeration_values : []string,
	t_union : union {
		xs_date,
		xs_dateTime,
		EpochTimeEnumsType,
	}
}

t_EpochType_Enumeration := [?]string {  }

TIME_WINDOW_IS_RELATIVE_TO_TYPE :: "TimeWindowIsRelativeToType" 
TimeWindowIsRelativeToType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_TimeWindowIsRelativeToType_Enumeration := [?]string { "commandRelease", "timeLastVerifierPassed",  }

MEMBER_TYPE :: "MemberType" 
MemberType :: struct {
	base : NameDescriptionType,
	t_typeRef : NameReferenceType,
	t_initialValue : xs_string,

}

NON_NEGATIVE_LONG_TYPE :: "NonNegativeLongType" 
NonNegativeLongType :: struct {
	t_restriction : xs_long,

}

POSITIVE_LONG_TYPE :: "PositiveLongType" 
PositiveLongType :: struct {
	t_restriction : xs_long,

}

FLOAT_SIZE_IN_BITS_TYPE :: "FloatSizeInBitsType" 
FloatSizeInBitsType :: struct {
	t_restriction : PositiveLongType,
	t_enumeration_values : []string,

}

t_FloatSizeInBitsType_Enumeration := [?]string { "32", "64", "128",  }

SIZE_IN_BITS_TYPE :: "SizeInBitsType" 
SizeInBitsType :: struct {
	t_TerminationChar : xs_hexBinary,
	t_LeadingSize : LeadingSizeType,
	t_Fixed : Fixed,

}

STRING_CONTEXT_ALARM_LIST_TYPE :: "StringContextAlarmListType" 
StringContextAlarmListType :: struct {
	t_ContextAlarm : [dynamic]StringContextAlarmType,

}

BIT_ORDER_TYPE :: "BitOrderType" 
BitOrderType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_BitOrderType_Enumeration := [?]string { "leastSignificantBitFirst", "mostSignificantBitFirst",  }

ARGUMENT_BASE_TIME_DATA_TYPE :: "ArgumentBaseTimeDataType" 
ArgumentBaseTimeDataType :: struct {
	base : NameDescriptionType,
	t_Encoding : EncodingType,
	t_ReferenceTime : ReferenceTimeType,
	t_baseType : NameReferenceType,

}

SYNC_STRATEGY_TYPE :: "SyncStrategyType" 
SyncStrategyType :: struct {
	t_AutoInvert : AutoInvertType,
	t_verifyToLockGoodFrames : NonNegativeLongType,
	t_checkToLockGoodFrames : NonNegativeLongType,
	t_maxBitErrorsInSyncPattern : NonNegativeLongType,

}

ARGUMENT_BOOLEAN_DATA_TYPE :: "ArgumentBooleanDataType" 
ArgumentBooleanDataType :: struct {
	base : ArgumentBaseDataType,
	t_initialValue : xs_string,
	t_oneStringValue : xs_string,
	t_zeroStringValue : xs_string,

}

CONTEXT_CALIBRATOR_TYPE :: "ContextCalibratorType" 
ContextCalibratorType :: struct {
	t_ContextMatch : ContextMatchType,
	t_Calibrator : CalibratorType,

}

DATA_ENCODING_TYPE :: "DataEncodingType" 
DataEncodingType :: struct {
	t_ErrorDetectCorrect : ErrorDetectCorrectType,
	t_bitOrder : BitOrderType,
	t_byteOrder : ByteOrderType,

}

ALARM_CONDITIONS_TYPE :: "AlarmConditionsType" 
AlarmConditionsType :: struct {
	t_WatchAlarm : MatchCriteriaType,
	t_WarningAlarm : MatchCriteriaType,
	t_DistressAlarm : MatchCriteriaType,
	t_CriticalAlarm : MatchCriteriaType,
	t_SevereAlarm : MatchCriteriaType,

}

FLOAT_ENCODING_TYPE :: "FloatEncodingType" 
FloatEncodingType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_FloatEncodingType_Enumeration := [?]string { "IEEE754_1985", "IEEE754", "MILSTD_1750A", "DEC", "IBM", "TI",  }

CONTAINER_TYPE :: "ContainerType" 
ContainerType :: struct {
	base : NameDescriptionType,
	t_DefaultRateInStream : RateInStreamType,
	t_RateInStreamSet : RateInStreamSetType,
	t_BinaryEncoding : BinaryDataEncodingType,

}

POLYNOMIAL_CALIBRATOR_TYPE :: "PolynomialCalibratorType" 
PolynomialCalibratorType :: struct {
	base : BaseCalibratorType,
	t_Term : [dynamic]TermType,

}

INPUT_ALGORITHM_TYPE :: "InputAlgorithmType" 
InputAlgorithmType :: struct {
	base : SimpleAlgorithmType,
	t_InputSet : InputSetType,

}

ON_PARAMETER_UPDATE_TRIGGER_TYPE :: "OnParameterUpdateTriggerType" 
OnParameterUpdateTriggerType :: struct {
	base : BaseTriggerType,
	t_parameterRef : NameReferenceType,

}

STRING_DATA_TYPE :: "StringDataType" 
StringDataType :: struct {
	base : BaseDataType,
	t_SizeRangeInCharacters : IntegerRangeType,
	t_initialValue : xs_string,
	t_restrictionPattern : xs_string,
	t_characterWidth : CharacterWidthType,

}

VERIFIER_ENUMERATION_TYPE :: "VerifierEnumerationType" 
VerifierEnumerationType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_VerifierEnumerationType_Enumeration := [?]string { "release", "transferredToRange", "sentFromRange", "received", "accepted", "queued", "executing", "complete", "failed",  }

ON_CONTAINER_UPDATE_TRIGGER_TYPE :: "OnContainerUpdateTriggerType" 
OnContainerUpdateTriggerType :: struct {
	base : BaseTriggerType,
	t_containerRef : NameReferenceType,

}

FLOAT_RANGE_TYPE :: "FloatRangeType" 
FloatRangeType :: struct {
	t_minInclusive : xs_double,
	t_minExclusive : xs_double,
	t_maxInclusive : xs_double,
	t_maxExclusive : xs_double,

}

CONTEXT_MATCH_TYPE :: "ContextMatchType" 
ContextMatchType :: struct {
	base : MatchCriteriaType,

}

ARGUMENT_DIMENSION_TYPE :: "ArgumentDimensionType" 
ArgumentDimensionType :: struct {
	t_StartingIndex : ArgumentIntegerValueType,
	t_EndingIndex : ArgumentIntegerValueType,

}

FLOAT_PARAMETER_TYPE :: "FloatParameterType" 
FloatParameterType :: struct {
	base : FloatDataType,
	t_DefaultAlarm : NumericAlarmType,
	t_ContextAlarmList : NumericContextAlarmListType,

}

CHECKSUM_TYPE :: "ChecksumType" 
ChecksumType :: struct {
	t_InputAlgorithm : InputAlgorithmType,
	t_bitsFromReference : NonNegativeLongType,
	t_reference : ReferencePointType,
	t_hashSizeInBits : PositiveLongType,
	t_enumerations_string:[14] string,
	t_restriction : xs_string,

}

t_ChecksumType_Enumeration := [?]string { "unix_sum", "sum8", "sum16", "sum24", "sum32", "fletcher4", "fletcher8", "fletcher16", "fletcher32", "adler32", "luhn", "verhoeff", "damm", "custom",  }

ARRAY_ARGUMENT_TYPE :: "ArrayArgumentType" 
ArrayArgumentType :: struct {
	base : ArrayDataTypeType,
	t_DimensionList : ArgumentDimensionListType,

}

AUTHOR_TYPE :: "AuthorType" 
AuthorType :: struct {
	t_restriction : xs_string,

}

TIME_ASSOCIATION_TYPE :: "TimeAssociationType" 
TimeAssociationType :: struct {
	base : ParameterInstanceRefType,
	t_interpolateTime : xs_boolean,
	t_offset : xs_double,
	t_unit : TimeAssociationUnitType,

}

ARGUMENT_TYPE_SET_TYPE :: "ArgumentTypeSetType" 
ArgumentTypeSetType :: struct {
	t_choice_0 : [dynamic]t_ArgumentTypeSetType0,

}

t_ArgumentTypeSetType0:: union {
	AggregateArgumentType,
	ArrayArgumentType,
	AbsoluteTimeArgumentType,
	RelativeTimeArgumentType,
	BooleanArgumentType,
	FloatArgumentType,
	BinaryArgumentType,
	IntegerArgumentType,
	EnumeratedArgumentType,
	StringArgumentType,
}

SERVICE_TYPE :: "ServiceType" 
ServiceType :: struct {
	base : NameDescriptionType,
	t_choice_0 : t_ServiceType0,

}

t_ServiceType0:: union {
	ContainerRefSetType,
	MessageRefSetType,
}

SERVICE_REF_TYPE :: "ServiceRefType" 
ServiceRefType :: struct {
	base : NameReferenceType,
	t_serviceRef : NameReferenceType,

}

NUMERIC_CONTEXT_ALARM_TYPE :: "NumericContextAlarmType" 
NumericContextAlarmType :: struct {
	base : NumericAlarmType,
	t_ContextMatch : ContextMatchType,

}

HEADER_TYPE :: "HeaderType" 
HeaderType :: struct {
	t_AuthorSet : AuthorSetType,
	t_NoteSet : NoteSetType,
	t_HistorySet : HistorySetType,
	t_version : xs_string,
	t_date : xs_string,
	t_classification : xs_string,
	t_classificationInstructions : xs_string,
	t_validationStatus : ValidationStatusType,

}

BYTE_TYPE :: "ByteType" 
ByteType :: struct {
	t_byteSignificance : NonNegativeLongType,

}

ARGUMENT_INPUT_ALGORITHM_TYPE :: "ArgumentInputAlgorithmType" 
ArgumentInputAlgorithmType :: struct {
	base : SimpleAlgorithmType,
	t_InputSet : ArgumentInputSetType,

}

CHARACTER_WIDTH_TYPE :: "CharacterWidthType" 
CharacterWidthType :: struct {
	t_restriction : xs_integer,
	t_enumeration_values : []string,

}

t_CharacterWidthType_Enumeration := [?]string { "8", "16",  }

SYNC_PATTERN_TYPE :: "SyncPatternType" 
SyncPatternType :: struct {
	t_pattern : xs_hexBinary,
	t_bitLocationFromStartOfContainer : xs_long,
	t_mask : xs_hexBinary,
	t_maskLengthInBits : PositiveLongType,
	t_patternLengthInBits : PositiveLongType,

}

OUTPUT_PARAMETER_REF_TYPE :: "OutputParameterRefType" 
OutputParameterRefType :: struct {
	base : ParameterRefType,
	t_outputName : xs_string,

}

CONSTANT_TYPE :: "ConstantType" 
ConstantType :: struct {
	t_constantName : xs_string,
	t_value : xs_string,

}

AGGREGATE_DATA_TYPE :: "AggregateDataType" 
AggregateDataType :: struct {
	base : NameDescriptionType,
	t_MemberList : MemberListType,

}

LONG_DESCRIPTION_TYPE :: "LongDescriptionType" 
LongDescriptionType :: struct {
	t_restriction : xs_string,

}

VALUE_ENUMERATION_TYPE :: "ValueEnumerationType" 
ValueEnumerationType :: struct {
	t_value : xs_long,
	t_maxValue : xs_long,
	t_label : xs_string,
	t_shortDescription : ShortDescriptionType,

}

PARAMETER_TYPE_SET_TYPE :: "ParameterTypeSetType" 
ParameterTypeSetType :: struct {
	t_choice_0 : [dynamic]t_ParameterTypeSetType0,

}

t_ParameterTypeSetType0:: union {
	AggregateParameterType,
	ArrayParameterType,
	AbsoluteTimeParameterType,
	RelativeTimeParameterType,
	BooleanParameterType,
	FloatParameterType,
	BinaryParameterType,
	IntegerParameterType,
	EnumeratedParameterType,
	StringParameterType,
}

COMMAND_META_DATA_TYPE :: "CommandMetaDataType" 
CommandMetaDataType :: struct {
	t_ParameterTypeSet : ParameterTypeSetType,
	t_ParameterSet : ParameterSetType,
	t_ArgumentTypeSet : ArgumentTypeSetType,
	t_MetaCommandSet : MetaCommandSetType,
	t_CommandContainerSet : CommandContainerSetType,
	t_StreamSet : StreamSetType,
	t_AlgorithmSet : AlgorithmSetType,

}

EXTERNAL_ALGORITHM_TYPE :: "ExternalAlgorithmType" 
ExternalAlgorithmType :: struct {
	t_implementationName : xs_string,
	t_algorithmLocation : xs_string,

}

BASE_CONTAINER_TYPE :: "BaseContainerType" 
BaseContainerType :: struct {
	t_RestrictionCriteria : RestrictionCriteriaType,
	t_containerRef : NameReferenceType,

}

CONTAINER_SET_TYPE :: "ContainerSetType" 
ContainerSetType :: struct {
	t_choice_0 : [dynamic]t_ContainerSetType0,

}

t_ContainerSetType0:: union {
	SequenceContainerType,
}

ON_PERIODIC_RATE_TRIGGER_TYPE :: "OnPeriodicRateTriggerType" 
OnPeriodicRateTriggerType :: struct {
	base : BaseTriggerType,
	t_fireRateInSeconds : xs_double,

}

ENUMERATED_DATA_TYPE :: "EnumeratedDataType" 
EnumeratedDataType :: struct {
	base : BaseDataType,
	t_EnumerationList : EnumerationListType,
	t_initialValue : xs_string,

}

OPTIONAL_NAME_DESCRIPTION_TYPE :: "OptionalNameDescriptionType" 
OptionalNameDescriptionType :: struct {
	base : DescriptionType,
	t_name : NameType,

}

INPUT_OUTPUT_ALGORITHM_TYPE :: "InputOutputAlgorithmType" 
InputOutputAlgorithmType :: struct {
	base : InputAlgorithmType,
	t_OutputSet : OutputSetType,
	t_thread : xs_boolean,

}

ENUMERATED_PARAMETER_TYPE :: "EnumeratedParameterType" 
EnumeratedParameterType :: struct {
	base : EnumeratedDataType,
	t_DefaultAlarm : EnumerationAlarmType,
	t_ContextAlarmList : EnumerationContextAlarmListType,

}

FLAG_TYPE :: "FlagType" 
FlagType :: struct {
	t_flagSizeInBits : PositiveLongType,
	t_flagBitType : FlagBitType,

}

ARGUMENT_LIST_TYPE :: "ArgumentListType" 
ArgumentListType :: struct {
	t_Argument : [dynamic]ArgumentType,

}

PARITY_FORM_TYPE :: "ParityFormType" 
ParityFormType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_ParityFormType_Enumeration := [?]string { "Even", "Odd",  }

STRING_ALARM_LEVEL_TYPE :: "StringAlarmLevelType" 
StringAlarmLevelType :: struct {
	t_alarmLevel : ConcernLevelsType,
	t_matchPattern : xs_string,

}

MATH_OPERATION_TYPE :: "MathOperationType" 
MathOperationType :: struct {
	base : MathOperationCalibratorType,

}

ANCILLARY_DATA_SET_TYPE :: "AncillaryDataSetType" 
AncillaryDataSetType :: struct {
	t_AncillaryData : [dynamic]AncillaryDataType,

}

ARGUMENT_O_RED_CONDITIONS_TYPE :: "ArgumentORedConditionsType" 
ArgumentORedConditionsType :: struct {
	base : BaseConditionsType,
	t_choice_0 : [2][dynamic]t_ArgumentORedConditionsType0,

}

t_ArgumentORedConditionsType0:: union {
	ArgumentANDedConditionsType,
	ArgumentComparisonCheckType,
}

OUTPUT_SET_TYPE :: "OutputSetType" 
OutputSetType :: struct {
	t_OutputParameterRef : [dynamic]OutputParameterRefType,

}

ALGORITHM_SET_TYPE :: "AlgorithmSetType" 
AlgorithmSetType :: struct {
	t_choice_0 : [dynamic]t_AlgorithmSetType0,

}

t_AlgorithmSetType0:: union {
	MathAlgorithmType,
	InputOutputTriggerAlgorithmType,
}

BASE_DATA_TYPE :: "BaseDataType" 
BaseDataType :: struct {
	base : NameDescriptionType,
	t_UnitSet : UnitSetType,
	t_baseType : NameReferenceType,
	t_choice_0 : t_BaseDataType0,

}

t_BaseDataType0:: union {
	StringDataEncodingType,
	IntegerDataEncodingType,
	FloatDataEncodingType,
	BinaryDataEncodingType,
}

OCTAL_TYPE :: "OctalType" 
OctalType :: struct {
	t_restriction : xs_string,

}

PARAMETERS_TO_SUSPEND_ALARMS_ON_SET_TYPE :: "ParametersToSuspendAlarmsOnSetType" 
ParametersToSuspendAlarmsOnSetType :: struct {
	t_ParameterToSuspendAlarmsOn : [dynamic]ParameterToSuspendAlarmsOnType,

}

SERVICE_SET_TYPE :: "ServiceSetType" 
ServiceSetType :: struct {
	t_Service : [dynamic]ServiceType,

}

LINEAR_ADJUSTMENT_TYPE :: "LinearAdjustmentType" 
LinearAdjustmentType :: struct {
	t_slope : xs_double,
	t_intercept : xs_double,

}

UNIT_TYPE :: "UnitType" 
UnitType :: struct {
	t_power : xs_double,
	t_factor : xs_string,
	t_description : ShortDescriptionType,
	t_form : UnitFormType,

}

VALID_FLOAT_RANGE_SET_TYPE :: "ValidFloatRangeSetType" 
ValidFloatRangeSetType :: struct {
	t_ValidRange : [dynamic]FloatRangeType,
	t_validRangeAppliesToCalibrated : xs_boolean,

}

ENUMERATED_ARGUMENT_TYPE :: "EnumeratedArgumentType" 
EnumeratedArgumentType :: struct {
	base : ArgumentEnumeratedDataType,

}

COMPARISON_OPERATORS_TYPE :: "ComparisonOperatorsType" 
ComparisonOperatorsType :: struct {
	t_restriction : xs_string,
	t_enumeration_values : []string,

}

t_ComparisonOperatorsType_Enumeration := [?]string { "==", "!=", "<", "<=", ">", ">=",  }

ARGUMENT_FLOAT_DATA_TYPE :: "ArgumentFloatDataType" 
ArgumentFloatDataType :: struct {
	base : ArgumentBaseDataType,
	t_ToString : ToStringType,
	t_initialValue : xs_double,
	t_sizeInBits : FloatSizeInBitsType,

}

BOOLEAN_ALARM_TYPE :: "BooleanAlarmType" 
BooleanAlarmType :: struct {
	base : AlarmType,

}

SIGNIFICANCE_TYPE :: "SignificanceType" 
SignificanceType :: struct {
	t_spaceSystemAtRisk : NameReferenceType,
	t_reasonForWarning : xs_string,
	t_consequenceLevel : ConsequenceLevelType,

}

TELEMETRY_META_DATA_TYPE :: "TelemetryMetaDataType" 
TelemetryMetaDataType :: struct {
	t_ParameterTypeSet : ParameterTypeSetType,
	t_ParameterSet : ParameterSetType,
	t_ContainerSet : ContainerSetType,
	t_MessageSet : MessageSetType,
	t_StreamSet : StreamSetType,
	t_AlgorithmSet : AlgorithmSetType,

}

ARGUMENT_ARGUMENT_REF_ENTRY_TYPE :: "ArgumentArgumentRefEntryType" 
ArgumentArgumentRefEntryType :: struct {
	base : ArgumentSequenceEntryType,
	t_argumentRef : NameReferenceType,

}

STREAM_SET_TYPE :: "StreamSetType" 
StreamSetType :: struct {
	t_choice_0 : [dynamic]t_StreamSetType0,

}

t_StreamSetType0:: union {
	CustomStreamType,
	VariableFrameStreamType,
	FixedFrameStreamType,
}

MESSAGE_REF_SET_TYPE :: "MessageRefSetType" 
MessageRefSetType :: struct {
	t_MessageRef : [dynamic]MessageRefType,

}


-- There is no bicycle animation, so riders reuse a stock vehicle sequence. Runs on both realms so the pose matches.
hook.Add("CalcMainActivity", "bicycle.riderPose", function(player)
  if (not bicycle.isSeat(player:GetVehicle())) then
    return
  end

  local sequence = player:LookupSequence(bicycle.getTuningString("rider_seq"))

  if (not sequence or sequence < 0) then
    sequence = player:LookupSequence(bicycle.DEFAULT_RIDER_SEQUENCE)
  end

  return ACT_HL2MP_SIT, sequence
end)

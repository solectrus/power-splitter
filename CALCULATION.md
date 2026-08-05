# How the calculation works

The Power Splitter answers one question, once per minute and for every consumer:
how much of the electricity it just used came from the grid? The rest came from
the sun.

Grid electricity can arrive on two paths: imported and used right away, or
imported earlier, stored in the home battery and taken out later. Both count, and
the calculation looks at both.

## An example

The house is consuming 3000 W - the heat pump 2000 W, everything else 1000 W. Of
that, 300 W are imported from the grid and 1800 W come out of the battery. The
remaining 900 W come straight from the roof.

Both the grid import and the battery discharge are shared out in proportion to
what each consumer uses. The heat pump takes two of every three watts, so it gets
two thirds of each:

| Consumer        | Uses   | Of the 300 W from the grid | Of the 1800 W from the battery |
| --------------- | ------ | -------------------------- | ------------------------------ |
| Heat pump       | 2000 W | 200 W                      | 1200 W                         |
| Everything else | 1000 W | 100 W                      | 600 W                          |

Whether the heat pump's 1200 W from the battery count as grid electricity depends
on what the battery holds:

| Stored in the battery  | `heatpump_power_grid` | Solar share of the heat pump |
| ---------------------- | --------------------- | ---------------------------- |
| Only grid electricity  | 200 + 1200 = 1400 W   | 600 W                        |
| Half grid, half solar  | 200 + 600 = 800 W     | 1200 W                       |
| Only solar electricity | 200 W                 | 1800 W                       |

These are three points on a sliding scale - a battery is rarely all of one or the
other. Whatever share of grid electricity it holds is applied to everybody who
takes something out of it. Keeping track of that share is what the ledger below
does.

## Sharing out the grid import

The wallbox is served first. Charging a car is a deliberate act, usually at a
time of the owner's choosing, so it gets its share before everybody else.

What is left over is shared out in proportion to consumption, and no consumer
ever gets more than it actually uses. While the battery is charging it takes part
like any other consumer - its share is what the ledger books as grid electricity
going into the battery.

One detail about house power: it is normally measured as a total that already
contains the heat pump, the wallbox and other devices. Everything listed in
`INFLUX_EXCLUDE_FROM_HOUSE_POWER` is subtracted from it first, so that it can be
shown separately instead. Custom consumers that are not listed stay part of house
power and are only broken out of it - they do not add to the total consumption.

## Sharing out the battery

Electricity from the battery is not automatically solar. If the battery was
charged from the grid earlier - during cheap hours, or by an emergency charge in
winter - what comes out of it was bought, not generated.

### The ledger

To tell those apart, the Power Splitter keeps a running balance of how much grid
electricity is sitting in the battery:

| Event                                     | Booking                                 |
| ----------------------------------------- | --------------------------------------- |
| Battery charges while importing from grid | Add what went in                        |
| Battery discharges                        | Take out, as far as the balance reaches |

Grid electricity is always taken out first. As long as the balance holds
something, electricity leaving the battery counts as grid electricity; once the
balance is empty, it counts as solar again.

Over a day with an emergency charge at night, the balance moves like this:

| Time  | What happens                        | Counts as grid | `battery_energy_grid` |
| ----- | ----------------------------------- | -------------- | --------------------- |
| 02:00 | 3000 Wh charged from the grid       | -              | 3000 Wh               |
| 09:00 | 4000 Wh charged from the sun        | -              | 3000 Wh               |
| 18:00 | Heat pump takes out 2000 Wh         | 2000 Wh        | 1000 Wh               |
| 21:00 | The house takes out another 2000 Wh | 1000 Wh        | 0 Wh                  |

Charging from the sun leaves the balance untouched - only grid electricity is
booked. And in the evening the balance runs out halfway through: of the 2000 Wh
the house takes, 1000 Wh still count as grid electricity and the rest as solar.

Add up the third column and the useful part of the rule shows:

> Exactly as much grid electricity leaves the battery as was put into it - no
> more, no less.

And from that follows: the solar consumption reported can never be higher than
what the panels actually produced. The Power Splitter arrives there without ever
looking at the solar production.

### The distribution

The whole discharge is shared out, not just its grid part. It goes to the
consumers with whatever the grid import did not already cover, by the same rules
as before: wallbox first, then in proportion. The battery does not receive its
own discharge.

Only afterwards does the ledger say what share of it was grid electricity. When
the balance covers the whole discharge, all of it counts as grid; when it runs
out halfway through, half of it does. That one share then applies to every
consumer alike.

The balance is reduced by what actually reached the consumers. If part of the
discharge cannot be handed out because every consumer is already covered, the
grid electricity behind it stays in the battery and is paid out later.

## What comes out

The results are averaged into five-minute values and stored in the
`power_splitter` measurement. Averaged over the minutes that could be split, not
over each field's own minutes: the shares of the consumers are meant to add up
(see below), and they only do so if they are divided by the same number. A
consumer whose sensor is silent for part of the period drew nothing from the
grid while it was gone - its share went to the others.

| Field                            | Meaning                                                |
| -------------------------------- | ------------------------------------------------------ |
| `<consumer>_power_grid`          | Grid share of that consumer                            |
| `battery_charging_power_grid`    | Grid share of what went into the battery               |
| `battery_discharging_power_grid` | Grid share of what the battery handed to the consumers |
| `battery_energy_grid`            | Grid electricity currently sitting in the battery (Wh) |

The last two only when both battery sensors are configured - which is also what
decides whether `<consumer>_power_grid` includes the part that came via the
battery. Without the discharge sensor there is nothing to attribute.

Nothing else is stored, because nothing else has to be. SOLECTRUS works out the
solar share of a consumer as the difference between its power and its grid share.

### Why the discharge share is stored separately

Without the battery, the grid shares of all consumers add up to the power
imported from the grid - there was nowhere else for grid electricity to come
from. With it, the battery becomes a second source, and the shares add up to
more:

```
Σ <consumer>_power_grid  =  grid_import_power + battery_discharging_power_grid
```

The extra term is reported in its own right, for anything that wants to balance
these fields to take into account.

SOLECTRUS does: its `SummaryCorrector` scales the `_grid` values so that they
add up again, which smooths out rounding errors. It has to use the sum above as
its target - otherwise it would scale away exactly the share that was attributed
here. Without the battery sensors the extra term is missing and the target is the
plain grid import, as it has always been.

#### Why not derive it from the balance

It would be possible. What leaves the battery is what went in minus what the
balance went up by, so over a timeframe, as energies:

```
Σ battery_discharging_power_grid  =  Σ battery_charging_power_grid - Δ battery_energy_grid
```

Storing it anyway is a deliberate trade. The balance is a value at the end of a
period, not something that can be summed or averaged, so reading it needs an
aggregation of its own - and the difference reaches back to the last period
*before* the timeframe, which makes a daily figure depend on the day before it.
On top of that, the term would be built from a value that a corrector scales at
the same time, which turns a straight sum into something that has to be solved
for.

The accuracy is the weaker point, though. A period is not always complete -
minutes can be missing. The charged share is an average, so averaging what is
there and reading it as a full period overstates it; the balance is a value at
the end and stays right either way. Subtracting the one from the other therefore
drifts in one direction. Reported directly, the value is an average like any
other power here, and carries that error once rather than as a difference of two
unlike ones.

## Recalculating

Every minute is calculated on its own, with one exception: the ledger balance
carries over from one minute to the next, and from one day to the next.

Days are therefore always processed in order, and the balance is stored in the
database rather than only kept in memory. A day gets recalculated many times -
today's data on every run - and reading the balance back means every one of those
runs starts from the same value and produces the same result.

Only the last two hours are searched for it. The balance is written for every
period that has data, so anything older means there is a gap, and after a gap the
ledger starts empty: a balance from before a gap would be a guess rather than a
measurement. The same holds inside a day - a minute missing between two others
marks such a gap just as well, and the ledger does not cross it either. Nor does
it cross a minute that is there but lost one of the four sensors it is built
from: the grid import and the house power, without which the charge cannot be
told apart from PV, and the two battery sensors, which are the deposit and the
withdrawal themselves. A minute only loses a sensor after two hours of silence
from it, so by then the battery may have been filled or emptied unseen. A full
rebuild deletes the stored data along with the ledger and builds it up again
from where the sensor data begins, at the earliest from the installation date.

Two hours is also how long a measured value is carried forward: sensors report
irregularly, so the last one has to cover the moments in between - and every
minute gets one, however rarely the sensors themselves report. Past that,
silence means the data stopped rather than the value standing still, and those
minutes are skipped entirely - nothing is calculated or stored for them, which is
what makes the two hours above find nothing. Without the limit, data that stops
arriving would look like a constant load for the rest of the day, and every watt
of it would be booked into the ledger and paid out on the days after.

The carry-forward shapes the minute itself as well: a value counts for as long as
it stood, not once per reading. A sensor that reports only when its value changes
would otherwise weigh a reading that lasted five seconds like one that lasted the
whole minute.

The day boundary is not special here either. A day is read together with the two
hours before it, so that both the silence and the last measured value carry over
midnight. Read on its own, a day would start with two hours of minutes that look
freshly reported - and a gap running over midnight would come back as minutes
present but empty, which is exactly what a gap must not look like.

## The rules, as tests

Everything above is prose, and prose cannot be executed. The rules that must
hold no matter what the data looks like are therefore written down a second
time, as tests over randomly generated days - `spec/invariants_spec.rb`:

- the consumers add up to what came in
- the ledger holds what was put in, no more and never less than nothing
- a gap empties the ledger
- a day can be calculated on its own

Their seam - a day read, split and seeded on its own, while a gap or the
carry-forward reaches over midnight - is where the mistakes were, so it is
tested end to end against a real query in `spec/day_boundary_spec.rb`.

Read those two files to find out what the calculation promises. If a change
breaks one of them, it breaks one of the four rules above.

## Where it is not exact

- **Measurements are averaged per minute.** If the battery charges for 20 seconds
  and the grid is used during the other 40, the averages make it look as if both
  happened at once, and a little grid electricity is booked into the battery that
  never went there. There is no way around that with this data.
- **Storage losses count against the grid share.** Charging and discharging are
  both measured outside the battery, so whatever is lost on the way through ends
  up in the ledger. The error makes the solar share look slightly smaller than it
  is, which is the safer direction to be wrong in.

## What it does not try to do

- **Model the whole system.** The Power Splitter never looks at solar production
  or feed-in. Tracking every flow would be more correct in theory, but on real
  installations the numbers never add up exactly, and it would need a lot more
  configuration for little gain.
- **Calculate costs.** The Power Splitter deals in kilowatt-hours, SOLECTRUS
  turns them into money. With a fixed tariff the grid share is all it takes,
  because the price does not depend on when the electricity was bought. With a
  dynamic tariff it does: electricity used directly costs today's price, while
  electricity from the battery cost whatever it cost back then. Telling those
  apart would need the battery share of every consumer stored as well, which is
  not done as long as nothing can make use of it.

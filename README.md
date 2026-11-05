# Activity Timers

overall vision

you can create different types of activity in the app and give each one a name
and you can also put them in groups which you give a name to each group

there is a button to start each activity
starting one automatically stops any other that are in progress if any others are in progress
there is also a button to stop, in case you want to stop without starting another one

in the fullness of time, there will be a lock screen widget that shows some compact stats of how much time you've had on each activity today
and when you click the widget it goes to the screen where you have the buttons for starting/stopping activities

also i think i want a "live activity" when an activity is in progress that shows up on the home screen and also in the little bubble at
the top of the phone screen

there will also be a screen with various graphs of like how much time has been spent on each activity per day
or each group
will think more later about what stats exactly i want to show on this screen

for the initial prototype, let's get something simpler working end to end first:
- there is the screen that shows you all the types and has buttons for starting and the button for stopping
- (we'll insert the activity types directly into the db and not have a screen that lets you manage them from the app)
- also on the same screen next to each activity it shows how much time has been accumulated into this activity today
- it is all properly persisted to firestore
- there are no other screens or widgets or other clients yet


import json
import os
import time

import Live
from _Framework.ControlSurface import ControlSurface


def create_instance(c_instance):
    return RetryTake(c_instance)


class RetryTake(ControlSurface):
    """Retry the selected audio track in Arrangement from zero."""

    def __init__(self, c_instance):
        super(RetryTake, self).__init__(c_instance)
        self._binding = None
        self._busy = False
        self._last_press = 0
        self._previous_track = None
        self._previous_clips = ()
        self._previous_before = ()
        self._config = os.path.join(os.path.dirname(__file__), 'button.json')
        try:
            with open(self._config) as handle:
                self._binding = tuple(json.load(handle))
        except (OSError, ValueError, TypeError):
            pass
        self.show_message('RetryTake Arrangement ready' if self._binding else 'RetryTake: press your chosen pad ONCE to learn; it will not record yet')
        self.log_message('RetryTake Arrangement v3 loaded; binding=%s' % (self._binding,))

    def build_midi_map(self, midi_map_handle):
        super(RetryTake, self).build_midi_map(midi_map_handle)
        script_handle = self._c_instance.handle()
        bindings = [self._binding] if self._binding else (
            (kind, channel, number)
            for kind in (144, 176)
            for channel in range(16)
            for number in range(128)
        )
        for kind, channel, number in bindings:
            if kind == 144:
                Live.MidiMap.forward_midi_note(script_handle, midi_map_handle, channel, number)
            else:
                Live.MidiMap.forward_midi_cc(script_handle, midi_map_handle, channel, number)

    def receive_midi(self, midi_bytes):
        if len(midi_bytes) != 3:
            return
        status, number, value = midi_bytes
        kind = status & 240
        if kind not in (144, 176) or value == 0:
            return
        binding = (kind, status & 15, number)
        if self._binding is None:
            self._binding = binding
            try:
                with open(self._config, 'w') as handle:
                    json.dump(binding, handle)
            except OSError as error:
                self.log_message('RetryTake binding save: %s' % error)
            self.request_rebuild_midi_map()
            self.show_message('RetryTake pad learned. Select your audio track; next press records Arrangement from zero.')
            return
        if binding != self._binding or self._busy or time.monotonic() - self._last_press < 0.7:
            return
        self._last_press = time.monotonic()
        song = self.song()
        track = song.view.selected_track
        if track not in song.tracks or not track.can_be_armed or not track.has_audio_input or track.is_frozen:
            self.show_message('RetryTake: select an unfrozen audio track')
            return
        self._busy = True
        try:
            song.stop_playing()
            song.record_mode = False
            self.schedule_message(2, self._restart_arrangement, track)
        except Exception as error:
            self._fail(error)

    def _restart_arrangement(self, track):
        song = self.song()
        song.begin_undo_step()
        try:
            if self._previous_track == track:
                # Recording clips may only become visible after transport stops.
                previous = tuple(clip for clip in track.arrangement_clips
                                 if clip in self._previous_clips or
                                 (clip not in self._previous_before and clip.start_time == 0.0))
                for clip in previous:
                    if clip in track.arrangement_clips:
                        track.delete_clip(clip)
            self._previous_clips = ()
            self._previous_track = track
            before = tuple(track.arrangement_clips)
            self._previous_before = before
            self.application().view.show_view('Arranger')
            track.current_monitoring_state = 0
            for other in song.tracks:
                if other.can_be_armed:
                    other.arm = (other == track)
            song.back_to_arranger = False
            song.session_record = False
            song.loop = False
            song.punch_in = False
            song.punch_out = False
            song.current_song_time = 0.0
            song.record_mode = True
            song.start_playing()
            self.schedule_message(3, lambda: self._capture_take(track, before))
            self.log_message('RetryTake Arrangement: recording track %s from zero' % track.name)
            self.show_message('RetryTake: recording Arrangement from 0:00')
        except Exception as error:
            self._fail(error)
        finally:
            song.end_undo_step()
            self._busy = False

    def _capture_take(self, track, before):
        try:
            self._previous_clips = tuple(clip for clip in track.arrangement_clips if clip not in before)
            self.log_message('RetryTake Arrangement: tracking %d new clips' % len(self._previous_clips))
        except Exception as error:
            self.log_message('RetryTake take tracking error: %s' % error)

    def _fail(self, error):
        self._busy = False
        self.log_message('RetryTake Arrangement error: %s' % error)
        self.show_message('RetryTake failed; see Live Log.txt')

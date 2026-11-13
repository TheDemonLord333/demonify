import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of S
/// returned by `S.of(context)`.
///
/// Applications need to include `S.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: S.localizationsDelegates,
///   supportedLocales: S.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the S.supportedLocales
/// property.
abstract class S {
  S(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static S of(BuildContext context) {
    return Localizations.of<S>(context, S)!;
  }

  static const LocalizationsDelegate<S> delegate = _SDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('de')];

  /// No description provided for @appTitle.
  ///
  /// In de, this message translates to:
  /// **'Demonify'**
  String get appTitle;

  /// No description provided for @add.
  ///
  /// In de, this message translates to:
  /// **'Hinzufügen'**
  String get add;

  /// No description provided for @addToPlaylist.
  ///
  /// In de, this message translates to:
  /// **'Zur Playlist hinzufügen'**
  String get addToPlaylist;

  /// No description provided for @addToQueue.
  ///
  /// In de, this message translates to:
  /// **'Zur Warteschlange hinzufügen'**
  String get addToQueue;

  /// No description provided for @addedToQueue.
  ///
  /// In de, this message translates to:
  /// **'Zur Warteschlange hinzugefügt.'**
  String get addedToQueue;

  /// No description provided for @adminAddArtist.
  ///
  /// In de, this message translates to:
  /// **'Künstler hinzufügen …'**
  String get adminAddArtist;

  /// No description provided for @adminAddFeature.
  ///
  /// In de, this message translates to:
  /// **'Feature hinzufügen …'**
  String get adminAddFeature;

  /// No description provided for @adminArtistExists.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ existiert bereits (gleicher Name nach Normalisierung).'**
  String adminArtistExists(String name);

  /// No description provided for @adminArtistName.
  ///
  /// In de, this message translates to:
  /// **'Künstlername'**
  String get adminArtistName;

  /// No description provided for @adminArtistSearch.
  ///
  /// In de, this message translates to:
  /// **'Künstler suchen …'**
  String get adminArtistSearch;

  /// No description provided for @adminArtists.
  ///
  /// In de, this message translates to:
  /// **'Künstler'**
  String get adminArtists;

  /// No description provided for @adminArtistsSub.
  ///
  /// In de, this message translates to:
  /// **'Anlegen, umbenennen, Profilbilder'**
  String get adminArtistsSub;

  /// No description provided for @adminArtistsTitle.
  ///
  /// In de, this message translates to:
  /// **'Künstlerverwaltung'**
  String get adminArtistsTitle;

  /// No description provided for @adminChangeCover.
  ///
  /// In de, this message translates to:
  /// **'Cover ersetzen'**
  String get adminChangeCover;

  /// No description provided for @adminChooseAudio.
  ///
  /// In de, this message translates to:
  /// **'Audiodateien auswählen'**
  String get adminChooseAudio;

  /// No description provided for @adminChooseCover.
  ///
  /// In de, this message translates to:
  /// **'Cover auswählen'**
  String get adminChooseCover;

  /// No description provided for @adminCommitting.
  ///
  /// In de, this message translates to:
  /// **'Wird abgelegt …'**
  String get adminCommitting;

  /// No description provided for @adminConfirmHint.
  ///
  /// In de, this message translates to:
  /// **'Der Server prüft die Dateien, legt Künstler-, Typ- und Veröffentlichungsordner automatisch an und überschreibt keine vorhandenen Dateien.'**
  String get adminConfirmHint;

  /// No description provided for @adminConfirmUpload.
  ///
  /// In de, this message translates to:
  /// **'Upload bestätigen'**
  String get adminConfirmUpload;

  /// No description provided for @adminCreate.
  ///
  /// In de, this message translates to:
  /// **'Anlegen'**
  String get adminCreate;

  /// No description provided for @adminCreateArtist.
  ///
  /// In de, this message translates to:
  /// **'Neuen Künstler erstellen'**
  String get adminCreateArtist;

  /// No description provided for @adminCreateArtistNamed.
  ///
  /// In de, this message translates to:
  /// **'Neuen Künstler erstellen: „{name}“'**
  String adminCreateArtistNamed(String name);

  /// No description provided for @adminCreateInvite.
  ///
  /// In de, this message translates to:
  /// **'Einladung erstellen'**
  String get adminCreateInvite;

  /// No description provided for @adminCreateUser.
  ///
  /// In de, this message translates to:
  /// **'Benutzer anlegen'**
  String get adminCreateUser;

  /// No description provided for @adminDisable.
  ///
  /// In de, this message translates to:
  /// **'Sperren'**
  String get adminDisable;

  /// No description provided for @adminDisabled.
  ///
  /// In de, this message translates to:
  /// **'gesperrt'**
  String get adminDisabled;

  /// No description provided for @adminDisc.
  ///
  /// In de, this message translates to:
  /// **'Disc'**
  String get adminDisc;

  /// No description provided for @adminEnable.
  ///
  /// In de, this message translates to:
  /// **'Entsperren'**
  String get adminEnable;

  /// No description provided for @adminFeatures.
  ///
  /// In de, this message translates to:
  /// **'Features'**
  String get adminFeatures;

  /// No description provided for @adminGenre.
  ///
  /// In de, this message translates to:
  /// **'Genre'**
  String get adminGenre;

  /// No description provided for @adminInviteCreated.
  ///
  /// In de, this message translates to:
  /// **'Einladung erstellt (Link wird nur jetzt angezeigt)'**
  String get adminInviteCreated;

  /// No description provided for @adminInvites.
  ///
  /// In de, this message translates to:
  /// **'Einladungen'**
  String get adminInvites;

  /// No description provided for @adminIssues.
  ///
  /// In de, this message translates to:
  /// **'Offene Probleme'**
  String get adminIssues;

  /// No description provided for @adminJobs.
  ///
  /// In de, this message translates to:
  /// **'Aufträge & Probleme'**
  String get adminJobs;

  /// No description provided for @adminJobsSub.
  ///
  /// In de, this message translates to:
  /// **'Bibliotheksscan, Fortschritt, Fehler'**
  String get adminJobsSub;

  /// No description provided for @adminMakeAdmin.
  ///
  /// In de, this message translates to:
  /// **'Zum Admin machen'**
  String get adminMakeAdmin;

  /// No description provided for @adminMakeUser.
  ///
  /// In de, this message translates to:
  /// **'Zum Benutzer machen'**
  String get adminMakeUser;

  /// No description provided for @adminNewRelease.
  ///
  /// In de, this message translates to:
  /// **'Neue Veröffentlichung ({type}) anlegen'**
  String adminNewRelease(String type);

  /// No description provided for @adminNoArtistFound.
  ///
  /// In de, this message translates to:
  /// **'Keine passenden Künstler gefunden.'**
  String get adminNoArtistFound;

  /// No description provided for @adminOpenRelease.
  ///
  /// In de, this message translates to:
  /// **'Veröffentlichung öffnen'**
  String get adminOpenRelease;

  /// No description provided for @adminOwnCover.
  ///
  /// In de, this message translates to:
  /// **'eigenes Cover'**
  String get adminOwnCover;

  /// No description provided for @adminReleaseCount.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Veröffentlichung} other{{count} Veröffentlichungen}}'**
  String adminReleaseCount(int count);

  /// No description provided for @adminReleaseCover.
  ///
  /// In de, this message translates to:
  /// **'Veröffentlichungscover'**
  String get adminReleaseCover;

  /// No description provided for @adminReleaseSearch.
  ///
  /// In de, this message translates to:
  /// **'Veröffentlichung suchen …'**
  String get adminReleaseSearch;

  /// No description provided for @adminReleaseTitle.
  ///
  /// In de, this message translates to:
  /// **'Titel'**
  String get adminReleaseTitle;

  /// No description provided for @adminReleasesSub.
  ///
  /// In de, this message translates to:
  /// **'Metadaten, Cover, Trackreihenfolge'**
  String get adminReleasesSub;

  /// No description provided for @adminReleasesTitle.
  ///
  /// In de, this message translates to:
  /// **'Veröffentlichungen'**
  String get adminReleasesTitle;

  /// No description provided for @adminRemoveArtistImage.
  ///
  /// In de, this message translates to:
  /// **'Profilbild entfernen'**
  String get adminRemoveArtistImage;

  /// No description provided for @adminRemoveSongCover.
  ///
  /// In de, this message translates to:
  /// **'Songcover entfernen (Veröffentlichungscover verwenden)'**
  String get adminRemoveSongCover;

  /// No description provided for @adminReplaceArtistImage.
  ///
  /// In de, this message translates to:
  /// **'Profilbild ersetzen'**
  String get adminReplaceArtistImage;

  /// No description provided for @adminReplaceSongCover.
  ///
  /// In de, this message translates to:
  /// **'Songcover ersetzen'**
  String get adminReplaceSongCover;

  /// No description provided for @adminResolve.
  ///
  /// In de, this message translates to:
  /// **'Als erledigt markieren'**
  String get adminResolve;

  /// No description provided for @adminReviewHint.
  ///
  /// In de, this message translates to:
  /// **'Titel, Künstler, Features, Nummern, Reihenfolge und individuelle Songcover prüfen. Ohne eigenes Songcover wird das Veröffentlichungscover verwendet.'**
  String get adminReviewHint;

  /// No description provided for @adminRevoke.
  ///
  /// In de, this message translates to:
  /// **'Widerrufen'**
  String get adminRevoke;

  /// No description provided for @adminRevokeSessions.
  ///
  /// In de, this message translates to:
  /// **'Alle Sitzungen beenden'**
  String get adminRevokeSessions;

  /// No description provided for @adminSaveOrder.
  ///
  /// In de, this message translates to:
  /// **'Reihenfolge speichern'**
  String get adminSaveOrder;

  /// No description provided for @adminSessions.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Sitzung} other{{count} Sitzungen}}'**
  String adminSessions(int count);

  /// No description provided for @adminSimilarArtists.
  ///
  /// In de, this message translates to:
  /// **'Ähnliche Namen (werden nicht zusammengeführt):'**
  String get adminSimilarArtists;

  /// No description provided for @adminSongCover.
  ///
  /// In de, this message translates to:
  /// **'Songcover zuordnen'**
  String get adminSongCover;

  /// No description provided for @adminStartPassword.
  ///
  /// In de, this message translates to:
  /// **'Startpasswort (mind. 10 Zeichen)'**
  String get adminStartPassword;

  /// No description provided for @adminStartScan.
  ///
  /// In de, this message translates to:
  /// **'Bibliotheksscan'**
  String get adminStartScan;

  /// No description provided for @adminStepArtist.
  ///
  /// In de, this message translates to:
  /// **'Künstler'**
  String get adminStepArtist;

  /// No description provided for @adminStepArtistHint.
  ///
  /// In de, this message translates to:
  /// **'Vorhandenen Künstler auswählen oder neuen anlegen – Vorschläge erscheinen ab dem ersten Buchstaben.'**
  String get adminStepArtistHint;

  /// No description provided for @adminStepConfirm.
  ///
  /// In de, this message translates to:
  /// **'Bestätigen'**
  String get adminStepConfirm;

  /// No description provided for @adminStepFiles.
  ///
  /// In de, this message translates to:
  /// **'Audiodateien'**
  String get adminStepFiles;

  /// No description provided for @adminStepMeta.
  ///
  /// In de, this message translates to:
  /// **'Metadaten & Cover'**
  String get adminStepMeta;

  /// No description provided for @adminStepRelease.
  ///
  /// In de, this message translates to:
  /// **'Veröffentlichung'**
  String get adminStepRelease;

  /// No description provided for @adminStepReview.
  ///
  /// In de, this message translates to:
  /// **'Prüfen'**
  String get adminStepReview;

  /// No description provided for @adminStepType.
  ///
  /// In de, this message translates to:
  /// **'Typ'**
  String get adminStepType;

  /// No description provided for @adminTitle.
  ///
  /// In de, this message translates to:
  /// **'Titel'**
  String get adminTitle;

  /// No description provided for @adminTrackArtistMissing.
  ///
  /// In de, this message translates to:
  /// **'Track {n}: mindestens ein Künstler nötig.'**
  String adminTrackArtistMissing(int n);

  /// No description provided for @adminTrackNo.
  ///
  /// In de, this message translates to:
  /// **'Nr.'**
  String get adminTrackNo;

  /// No description provided for @adminTrackNumberDuplicate.
  ///
  /// In de, this message translates to:
  /// **'Disc {disc}, Track {number} ist doppelt vergeben.'**
  String adminTrackNumberDuplicate(int disc, int number);

  /// No description provided for @adminTrackTitleMissing.
  ///
  /// In de, this message translates to:
  /// **'Track {n}: Titel fehlt.'**
  String adminTrackTitleMissing(int n);

  /// No description provided for @adminTracks.
  ///
  /// In de, this message translates to:
  /// **'Tracks'**
  String get adminTracks;

  /// No description provided for @adminType.
  ///
  /// In de, this message translates to:
  /// **'Typ'**
  String get adminType;

  /// No description provided for @adminUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Nicht verfügbare Dateien'**
  String get adminUnavailable;

  /// No description provided for @adminUpload.
  ///
  /// In de, this message translates to:
  /// **'Musik hochladen'**
  String get adminUpload;

  /// No description provided for @adminUploadAnother.
  ///
  /// In de, this message translates to:
  /// **'Weiteren Upload starten'**
  String get adminUploadAnother;

  /// No description provided for @adminUploadArtistImage.
  ///
  /// In de, this message translates to:
  /// **'Profilbild hochladen'**
  String get adminUploadArtistImage;

  /// No description provided for @adminUploadDone.
  ///
  /// In de, this message translates to:
  /// **'Upload abgeschlossen'**
  String get adminUploadDone;

  /// No description provided for @adminUploadSub.
  ///
  /// In de, this message translates to:
  /// **'Künstler, Veröffentlichung, Dateien – Ablage automatisch'**
  String get adminUploadSub;

  /// No description provided for @adminUploading.
  ///
  /// In de, this message translates to:
  /// **'Wird hochgeladen …'**
  String get adminUploading;

  /// No description provided for @adminUsers.
  ///
  /// In de, this message translates to:
  /// **'Benutzer'**
  String get adminUsers;

  /// No description provided for @adminUsersSub.
  ///
  /// In de, this message translates to:
  /// **'Benutzer, Rollen, Einladungen'**
  String get adminUsersSub;

  /// No description provided for @adminValidated.
  ///
  /// In de, this message translates to:
  /// **'Geprüft ✓'**
  String get adminValidated;

  /// No description provided for @adminValidating.
  ///
  /// In de, this message translates to:
  /// **'Wird geprüft …'**
  String get adminValidating;

  /// No description provided for @adminWaitingUploads.
  ///
  /// In de, this message translates to:
  /// **'Warte auf Abschluss und Prüfung aller Uploads …'**
  String get adminWaitingUploads;

  /// No description provided for @adminYear.
  ///
  /// In de, this message translates to:
  /// **'Jahr'**
  String get adminYear;

  /// No description provided for @allSongs.
  ///
  /// In de, this message translates to:
  /// **'Alle Songs'**
  String get allSongs;

  /// No description provided for @appVersion.
  ///
  /// In de, this message translates to:
  /// **'App-Version'**
  String get appVersion;

  /// No description provided for @appearsOn.
  ///
  /// In de, this message translates to:
  /// **'Enthalten in'**
  String get appearsOn;

  /// No description provided for @artistLabel.
  ///
  /// In de, this message translates to:
  /// **'Künstler'**
  String get artistLabel;

  /// No description provided for @artists.
  ///
  /// In de, this message translates to:
  /// **'Künstler'**
  String get artists;

  /// No description provided for @back.
  ///
  /// In de, this message translates to:
  /// **'Zurück'**
  String get back;

  /// No description provided for @cancel.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get cancel;

  /// No description provided for @cancelled.
  ///
  /// In de, this message translates to:
  /// **'Abgebrochen'**
  String get cancelled;

  /// No description provided for @change.
  ///
  /// In de, this message translates to:
  /// **'Ändern'**
  String get change;

  /// No description provided for @clear.
  ///
  /// In de, this message translates to:
  /// **'Leeren'**
  String get clear;

  /// No description provided for @clearQueue.
  ///
  /// In de, this message translates to:
  /// **'Leeren'**
  String get clearQueue;

  /// No description provided for @close.
  ///
  /// In de, this message translates to:
  /// **'Schließen'**
  String get close;

  /// No description provided for @copy.
  ///
  /// In de, this message translates to:
  /// **'Kopieren'**
  String get copy;

  /// No description provided for @delete.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get delete;

  /// No description provided for @discNumber.
  ///
  /// In de, this message translates to:
  /// **'Disc {n}'**
  String discNumber(int n);

  /// No description provided for @displayNameOptional.
  ///
  /// In de, this message translates to:
  /// **'Anzeigename (optional)'**
  String get displayNameOptional;

  /// No description provided for @done.
  ///
  /// In de, this message translates to:
  /// **'Fertig'**
  String get done;

  /// No description provided for @download.
  ///
  /// In de, this message translates to:
  /// **'Herunterladen'**
  String get download;

  /// No description provided for @downloadCollections.
  ///
  /// In de, this message translates to:
  /// **'Veröffentlichungen & Playlists'**
  String get downloadCollections;

  /// No description provided for @downloadFailed.
  ///
  /// In de, this message translates to:
  /// **'Fehlgeschlagen'**
  String get downloadFailed;

  /// No description provided for @downloadQuality.
  ///
  /// In de, this message translates to:
  /// **'Downloadqualität'**
  String get downloadQuality;

  /// No description provided for @downloadQueued.
  ///
  /// In de, this message translates to:
  /// **'Wartet …'**
  String get downloadQueued;

  /// No description provided for @downloading.
  ///
  /// In de, this message translates to:
  /// **'Wird heruntergeladen …'**
  String get downloading;

  /// No description provided for @downloads.
  ///
  /// In de, this message translates to:
  /// **'Downloads'**
  String get downloads;

  /// No description provided for @downloadsEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Downloads'**
  String get downloadsEmpty;

  /// No description provided for @downloadsEmptyHint.
  ///
  /// In de, this message translates to:
  /// **'Lade Songs, Veröffentlichungen oder Playlists herunter, um sie ohne Internet zu hören.'**
  String get downloadsEmptyHint;

  /// No description provided for @downloadsInProgress.
  ///
  /// In de, this message translates to:
  /// **'In Bearbeitung'**
  String get downloadsInProgress;

  /// No description provided for @downloadsRemoveAll.
  ///
  /// In de, this message translates to:
  /// **'Alle Downloads löschen'**
  String get downloadsRemoveAll;

  /// No description provided for @downloadsRemoveAllConfirm.
  ///
  /// In de, this message translates to:
  /// **'Alle heruntergeladenen Dateien dieses Kontos werden von diesem Gerät gelöscht.'**
  String get downloadsRemoveAllConfirm;

  /// No description provided for @downloadsRetryFailed.
  ///
  /// In de, this message translates to:
  /// **'Fehlgeschlagene wiederholen'**
  String get downloadsRetryFailed;

  /// No description provided for @downloadsServerNote.
  ///
  /// In de, this message translates to:
  /// **'Hinweis: Heruntergeladene Dateien liegen im privaten App-Speicher dieses Kontos. Wird ein Konto später gesperrt oder ein Song entfernt, bleiben bereits geladene Dateien bis zur nächsten Anmeldung/Abmeldung technisch auf dem Gerät erhalten.'**
  String get downloadsServerNote;

  /// No description provided for @eqActiveHint.
  ///
  /// In de, this message translates to:
  /// **'Wirkt auf Streaming und Offline-Wiedergabe.'**
  String get eqActiveHint;

  /// No description provided for @eqEnabled.
  ///
  /// In de, this message translates to:
  /// **'Equalizer'**
  String get eqEnabled;

  /// No description provided for @eqHeadroom.
  ///
  /// In de, this message translates to:
  /// **'Automatischer Headroom'**
  String get eqHeadroom;

  /// No description provided for @eqHeadroomHint.
  ///
  /// In de, this message translates to:
  /// **'Senkt die Gesamtlautstärke um die stärkste Anhebung, um Übersteuerung zu vermeiden (aktuell {db} dB).'**
  String eqHeadroomHint(String db);

  /// No description provided for @eqInactiveHint.
  ///
  /// In de, this message translates to:
  /// **'Aus – Wiedergabe unverändert.'**
  String get eqInactiveHint;

  /// No description provided for @eqInfoAirplay.
  ///
  /// In de, this message translates to:
  /// **'AirPlay und Bluetooth: Der Klang wird auf diesem Gerät berechnet und dann übertragen – der Equalizer wirkt also auch dort.'**
  String get eqInfoAirplay;

  /// No description provided for @eqInfoBody.
  ///
  /// In de, this message translates to:
  /// **'10 Bänder von 31 Hz bis 16 kHz, je −12 bis +12 dB. Die Dateien selbst werden nie verändert; Einstellungen gelten für dieses Konto auf diesem Gerät.'**
  String get eqInfoBody;

  /// No description provided for @eqInfoCast.
  ///
  /// In de, this message translates to:
  /// **'Bluetooth und Kopfhörer: Der Klang wird auf diesem Gerät berechnet – der Equalizer wirkt. Bei künftigem Casting (Wiedergabe direkt auf dem Zielgerät) wirkt er nicht.'**
  String get eqInfoCast;

  /// No description provided for @eqInfoTitle.
  ///
  /// In de, this message translates to:
  /// **'So funktioniert der Equalizer'**
  String get eqInfoTitle;

  /// No description provided for @eqPreamp.
  ///
  /// In de, this message translates to:
  /// **'Vorverstärkung'**
  String get eqPreamp;

  /// No description provided for @eqPresets.
  ///
  /// In de, this message translates to:
  /// **'Voreinstellungen'**
  String get eqPresets;

  /// No description provided for @eqUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Die Audioengine hat den Equalizer-Filter auf diesem Gerät nicht angenommen. Die Wiedergabe funktioniert weiterhin, aber ohne Klangverarbeitung.'**
  String get eqUnavailable;

  /// No description provided for @equalizer.
  ///
  /// In de, this message translates to:
  /// **'Equalizer'**
  String get equalizer;

  /// No description provided for @error.
  ///
  /// In de, this message translates to:
  /// **'Fehler'**
  String get error;

  /// No description provided for @errorGenericTitle.
  ///
  /// In de, this message translates to:
  /// **'Etwas ist schiefgelaufen'**
  String get errorGenericTitle;

  /// No description provided for @errorNetworkTitle.
  ///
  /// In de, this message translates to:
  /// **'Keine Verbindung'**
  String get errorNetworkTitle;

  /// No description provided for @favoriteAdd.
  ///
  /// In de, this message translates to:
  /// **'Zu Lieblingssongs hinzufügen'**
  String get favoriteAdd;

  /// No description provided for @favoriteRemove.
  ///
  /// In de, this message translates to:
  /// **'Aus Lieblingssongs entfernen'**
  String get favoriteRemove;

  /// No description provided for @favorites.
  ///
  /// In de, this message translates to:
  /// **'Lieblingssongs'**
  String get favorites;

  /// No description provided for @favoritesEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Lieblingssongs'**
  String get favoritesEmpty;

  /// No description provided for @favoritesEmptyHint.
  ///
  /// In de, this message translates to:
  /// **'Tippe auf das Herz, um Songs hier zu sammeln.'**
  String get favoritesEmptyHint;

  /// No description provided for @fieldRequired.
  ///
  /// In de, this message translates to:
  /// **'Pflichtfeld'**
  String get fieldRequired;

  /// No description provided for @follow.
  ///
  /// In de, this message translates to:
  /// **'Folgen'**
  String get follow;

  /// No description provided for @followedArtists.
  ///
  /// In de, this message translates to:
  /// **'Gefolgte Künstler'**
  String get followedArtists;

  /// No description provided for @following.
  ///
  /// In de, this message translates to:
  /// **'Folge ich'**
  String get following;

  /// No description provided for @goToArtistNamed.
  ///
  /// In de, this message translates to:
  /// **'Zu {name}'**
  String goToArtistNamed(String name);

  /// No description provided for @goToRelease.
  ///
  /// In de, this message translates to:
  /// **'Zur Veröffentlichung'**
  String get goToRelease;

  /// No description provided for @greetingDay.
  ///
  /// In de, this message translates to:
  /// **'Hallo'**
  String get greetingDay;

  /// No description provided for @greetingEvening.
  ///
  /// In de, this message translates to:
  /// **'Guten Abend'**
  String get greetingEvening;

  /// No description provided for @greetingMorning.
  ///
  /// In de, this message translates to:
  /// **'Guten Morgen'**
  String get greetingMorning;

  /// No description provided for @greetingName.
  ///
  /// In de, this message translates to:
  /// **'{greeting}, {name}'**
  String greetingName(String greeting, String name);

  /// No description provided for @hidePassword.
  ///
  /// In de, this message translates to:
  /// **'Passwort verbergen'**
  String get hidePassword;

  /// No description provided for @homeEmptyMessage.
  ///
  /// In de, this message translates to:
  /// **'Sobald Musik hochgeladen oder gescannt wurde, erscheint sie hier.'**
  String get homeEmptyMessage;

  /// No description provided for @homeEmptyTitle.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Musik in der Bibliothek'**
  String get homeEmptyTitle;

  /// No description provided for @inviteCode.
  ///
  /// In de, this message translates to:
  /// **'Einladungscode oder -link'**
  String get inviteCode;

  /// No description provided for @inviteRedeem.
  ///
  /// In de, this message translates to:
  /// **'Einladung einlösen'**
  String get inviteRedeem;

  /// No description provided for @inviteSubmit.
  ///
  /// In de, this message translates to:
  /// **'Konto erstellen'**
  String get inviteSubmit;

  /// No description provided for @inviteSuccess.
  ///
  /// In de, this message translates to:
  /// **'Konto erstellt – du kannst dich jetzt anmelden.'**
  String get inviteSuccess;

  /// No description provided for @jobCleanup.
  ///
  /// In de, this message translates to:
  /// **'Upload-Bereinigung'**
  String get jobCleanup;

  /// No description provided for @jobScan.
  ///
  /// In de, this message translates to:
  /// **'Bibliotheksscan'**
  String get jobScan;

  /// No description provided for @jobTranscode.
  ///
  /// In de, this message translates to:
  /// **'Transkodierung'**
  String get jobTranscode;

  /// No description provided for @libraryAll.
  ///
  /// In de, this message translates to:
  /// **'Alle'**
  String get libraryAll;

  /// No description provided for @libraryEmpty.
  ///
  /// In de, this message translates to:
  /// **'Hier ist noch nichts.'**
  String get libraryEmpty;

  /// No description provided for @libraryFollowed.
  ///
  /// In de, this message translates to:
  /// **'Gefolgt'**
  String get libraryFollowed;

  /// No description provided for @librarySaved.
  ///
  /// In de, this message translates to:
  /// **'Gespeichert'**
  String get librarySaved;

  /// No description provided for @login.
  ///
  /// In de, this message translates to:
  /// **'Anmelden'**
  String get login;

  /// No description provided for @loginChangeServer.
  ///
  /// In de, this message translates to:
  /// **'Serveradresse ändern'**
  String get loginChangeServer;

  /// No description provided for @loginSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Deine private Musikplattform'**
  String get loginSubtitle;

  /// No description provided for @logout.
  ///
  /// In de, this message translates to:
  /// **'Abmelden'**
  String get logout;

  /// No description provided for @logoutDeleteDownloads.
  ///
  /// In de, this message translates to:
  /// **'Downloads dieses Kontos von diesem Gerät löschen'**
  String get logoutDeleteDownloads;

  /// No description provided for @logoutMessage.
  ///
  /// In de, this message translates to:
  /// **'Du wirst auf diesem Gerät abgemeldet. Die Sitzung wird auch auf dem Server beendet.'**
  String get logoutMessage;

  /// No description provided for @logoutTitle.
  ///
  /// In de, this message translates to:
  /// **'Abmelden?'**
  String get logoutTitle;

  /// No description provided for @manageDownloads.
  ///
  /// In de, this message translates to:
  /// **'Downloads verwalten'**
  String get manageDownloads;

  /// No description provided for @moreActions.
  ///
  /// In de, this message translates to:
  /// **'Weitere Aktionen'**
  String get moreActions;

  /// No description provided for @navAdmin.
  ///
  /// In de, this message translates to:
  /// **'Verwaltung'**
  String get navAdmin;

  /// No description provided for @navHome.
  ///
  /// In de, this message translates to:
  /// **'Start'**
  String get navHome;

  /// No description provided for @navLibrary.
  ///
  /// In de, this message translates to:
  /// **'Bibliothek'**
  String get navLibrary;

  /// No description provided for @navSearch.
  ///
  /// In de, this message translates to:
  /// **'Suche'**
  String get navSearch;

  /// No description provided for @navSettings.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen'**
  String get navSettings;

  /// No description provided for @newReleases.
  ///
  /// In de, this message translates to:
  /// **'Neu hinzugefügt'**
  String get newReleases;

  /// No description provided for @next.
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get next;

  /// No description provided for @nothingPlaying.
  ///
  /// In de, this message translates to:
  /// **'Nichts in der Wiedergabe'**
  String get nothingPlaying;

  /// No description provided for @nowPlaying.
  ///
  /// In de, this message translates to:
  /// **'Wird gespielt'**
  String get nowPlaying;

  /// No description provided for @off.
  ///
  /// In de, this message translates to:
  /// **'Aus'**
  String get off;

  /// No description provided for @offlineBanner.
  ///
  /// In de, this message translates to:
  /// **'Offline – nur heruntergeladene Musik ist verfügbar.'**
  String get offlineBanner;

  /// No description provided for @on.
  ///
  /// In de, this message translates to:
  /// **'An'**
  String get on;

  /// No description provided for @openPlayer.
  ///
  /// In de, this message translates to:
  /// **'Player öffnen'**
  String get openPlayer;

  /// No description provided for @password.
  ///
  /// In de, this message translates to:
  /// **'Passwort'**
  String get password;

  /// No description provided for @passwordMismatch.
  ///
  /// In de, this message translates to:
  /// **'Die Passwörter stimmen nicht überein.'**
  String get passwordMismatch;

  /// No description provided for @passwordRepeat.
  ///
  /// In de, this message translates to:
  /// **'Passwort wiederholen'**
  String get passwordRepeat;

  /// No description provided for @passwordTooShort.
  ///
  /// In de, this message translates to:
  /// **'Mindestens 10 Zeichen.'**
  String get passwordTooShort;

  /// No description provided for @pause.
  ///
  /// In de, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @play.
  ///
  /// In de, this message translates to:
  /// **'Abspielen'**
  String get play;

  /// No description provided for @playNext.
  ///
  /// In de, this message translates to:
  /// **'Als Nächstes spielen'**
  String get playNext;

  /// No description provided for @playlist.
  ///
  /// In de, this message translates to:
  /// **'Playlist'**
  String get playlist;

  /// No description provided for @playlistAdded.
  ///
  /// In de, this message translates to:
  /// **'Zu „{name}“ hinzugefügt.'**
  String playlistAdded(String name);

  /// No description provided for @playlistCreate.
  ///
  /// In de, this message translates to:
  /// **'Erstellen'**
  String get playlistCreate;

  /// No description provided for @playlistDelete.
  ///
  /// In de, this message translates to:
  /// **'Playlist löschen'**
  String get playlistDelete;

  /// No description provided for @playlistDeleteConfirm.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ wirklich löschen?'**
  String playlistDeleteConfirm(String name);

  /// No description provided for @playlistEditOrder.
  ///
  /// In de, this message translates to:
  /// **'Reihenfolge bearbeiten'**
  String get playlistEditOrder;

  /// No description provided for @playlistEmpty.
  ///
  /// In de, this message translates to:
  /// **'Diese Playlist ist leer'**
  String get playlistEmpty;

  /// No description provided for @playlistEmptyHint.
  ///
  /// In de, this message translates to:
  /// **'Füge Songs über das Menü ⋮ eines Songs hinzu.'**
  String get playlistEmptyHint;

  /// No description provided for @playlistName.
  ///
  /// In de, this message translates to:
  /// **'Name der Playlist'**
  String get playlistName;

  /// No description provided for @playlistNew.
  ///
  /// In de, this message translates to:
  /// **'Neue Playlist'**
  String get playlistNew;

  /// No description provided for @playlistRemoveEntry.
  ///
  /// In de, this message translates to:
  /// **'Aus Playlist entfernen'**
  String get playlistRemoveEntry;

  /// No description provided for @playlistRename.
  ///
  /// In de, this message translates to:
  /// **'Umbenennen'**
  String get playlistRename;

  /// No description provided for @playlists.
  ///
  /// In de, this message translates to:
  /// **'Playlists'**
  String get playlists;

  /// No description provided for @popularSongs.
  ///
  /// In de, this message translates to:
  /// **'Beliebte Songs'**
  String get popularSongs;

  /// No description provided for @presetBassBoost.
  ///
  /// In de, this message translates to:
  /// **'Bass Boost'**
  String get presetBassBoost;

  /// No description provided for @presetCustom.
  ///
  /// In de, this message translates to:
  /// **'Benutzerdefiniert'**
  String get presetCustom;

  /// No description provided for @presetElectronic.
  ///
  /// In de, this message translates to:
  /// **'Elektronisch'**
  String get presetElectronic;

  /// No description provided for @presetNeutral.
  ///
  /// In de, this message translates to:
  /// **'Neutral'**
  String get presetNeutral;

  /// No description provided for @presetPop.
  ///
  /// In de, this message translates to:
  /// **'Pop'**
  String get presetPop;

  /// No description provided for @presetRock.
  ///
  /// In de, this message translates to:
  /// **'Rock'**
  String get presetRock;

  /// No description provided for @presetVocal.
  ///
  /// In de, this message translates to:
  /// **'Gesang'**
  String get presetVocal;

  /// No description provided for @previous.
  ///
  /// In de, this message translates to:
  /// **'Zurück'**
  String get previous;

  /// No description provided for @qualityHigh.
  ///
  /// In de, this message translates to:
  /// **'Hoch (AAC 256 kbit/s)'**
  String get qualityHigh;

  /// No description provided for @qualityHint.
  ///
  /// In de, this message translates to:
  /// **'Transkodierte Stufen werden beim ersten Abruf auf dem Server erzeugt; bis dahin wird das Original geliefert.'**
  String get qualityHint;

  /// No description provided for @qualityLow.
  ///
  /// In de, this message translates to:
  /// **'Datensparend (AAC 96 kbit/s)'**
  String get qualityLow;

  /// No description provided for @qualityNormal.
  ///
  /// In de, this message translates to:
  /// **'Normal (AAC 160 kbit/s)'**
  String get qualityNormal;

  /// No description provided for @qualityOriginal.
  ///
  /// In de, this message translates to:
  /// **'Original (verlustfrei, falls vorhanden)'**
  String get qualityOriginal;

  /// No description provided for @queue.
  ///
  /// In de, this message translates to:
  /// **'Warteschlange'**
  String get queue;

  /// No description provided for @queueEmpty.
  ///
  /// In de, this message translates to:
  /// **'Die Warteschlange ist leer'**
  String get queueEmpty;

  /// No description provided for @recentlyPlayed.
  ///
  /// In de, this message translates to:
  /// **'Zuletzt gehört'**
  String get recentlyPlayed;

  /// No description provided for @reconnect.
  ///
  /// In de, this message translates to:
  /// **'Verbinden'**
  String get reconnect;

  /// No description provided for @releases.
  ///
  /// In de, this message translates to:
  /// **'Veröffentlichungen'**
  String get releases;

  /// No description provided for @remove.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get remove;

  /// No description provided for @removeDownload.
  ///
  /// In de, this message translates to:
  /// **'Download entfernen'**
  String get removeDownload;

  /// No description provided for @removeDownloadConfirm.
  ///
  /// In de, this message translates to:
  /// **'Die heruntergeladenen Dateien werden von diesem Gerät gelöscht.'**
  String get removeDownloadConfirm;

  /// No description provided for @removeFromQueue.
  ///
  /// In de, this message translates to:
  /// **'Aus Warteschlange entfernen'**
  String get removeFromQueue;

  /// No description provided for @repeatAll.
  ///
  /// In de, this message translates to:
  /// **'Alle wiederholen'**
  String get repeatAll;

  /// No description provided for @repeatOff.
  ///
  /// In de, this message translates to:
  /// **'Wiederholung aus'**
  String get repeatOff;

  /// No description provided for @repeatOne.
  ///
  /// In de, this message translates to:
  /// **'Titel wiederholen'**
  String get repeatOne;

  /// No description provided for @reset.
  ///
  /// In de, this message translates to:
  /// **'Zurücksetzen'**
  String get reset;

  /// No description provided for @retry.
  ///
  /// In de, this message translates to:
  /// **'Erneut versuchen'**
  String get retry;

  /// No description provided for @roleAdmin.
  ///
  /// In de, this message translates to:
  /// **'Administrator'**
  String get roleAdmin;

  /// No description provided for @roleUser.
  ///
  /// In de, this message translates to:
  /// **'Benutzer'**
  String get roleUser;

  /// No description provided for @save.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get save;

  /// No description provided for @saved.
  ///
  /// In de, this message translates to:
  /// **'Gespeichert'**
  String get saved;

  /// No description provided for @searchEmptyMessage.
  ///
  /// In de, this message translates to:
  /// **'Suche nach Songs, Künstlern, Veröffentlichungen und deinen Playlists.'**
  String get searchEmptyMessage;

  /// No description provided for @searchEmptyTitle.
  ///
  /// In de, this message translates to:
  /// **'Was möchtest du hören?'**
  String get searchEmptyTitle;

  /// No description provided for @searchHint.
  ///
  /// In de, this message translates to:
  /// **'Songs, Künstler, Alben …'**
  String get searchHint;

  /// No description provided for @searchNoResults.
  ///
  /// In de, this message translates to:
  /// **'Keine Ergebnisse für „{query}“'**
  String searchNoResults(String query);

  /// No description provided for @select.
  ///
  /// In de, this message translates to:
  /// **'Auswählen'**
  String get select;

  /// No description provided for @serverAddress.
  ///
  /// In de, this message translates to:
  /// **'Serveradresse'**
  String get serverAddress;

  /// No description provided for @serverAddressHint.
  ///
  /// In de, this message translates to:
  /// **'z. B. demonify.thedemonlord333.me'**
  String get serverAddressHint;

  /// No description provided for @settingsAbout.
  ///
  /// In de, this message translates to:
  /// **'Über'**
  String get settingsAbout;

  /// No description provided for @settingsAccount.
  ///
  /// In de, this message translates to:
  /// **'Konto'**
  String get settingsAccount;

  /// No description provided for @settingsPlayback.
  ///
  /// In de, this message translates to:
  /// **'Wiedergabe & Downloads'**
  String get settingsPlayback;

  /// No description provided for @settingsSound.
  ///
  /// In de, this message translates to:
  /// **'Klang'**
  String get settingsSound;

  /// No description provided for @showAll.
  ///
  /// In de, this message translates to:
  /// **'Alle anzeigen'**
  String get showAll;

  /// No description provided for @showAllSongs.
  ///
  /// In de, this message translates to:
  /// **'Alle {count} Songs anzeigen'**
  String showAllSongs(int count);

  /// No description provided for @showPassword.
  ///
  /// In de, this message translates to:
  /// **'Passwort anzeigen'**
  String get showPassword;

  /// No description provided for @shuffle.
  ///
  /// In de, this message translates to:
  /// **'Zufallswiedergabe'**
  String get shuffle;

  /// No description provided for @shuffleOff.
  ///
  /// In de, this message translates to:
  /// **'Zufallswiedergabe aus'**
  String get shuffleOff;

  /// No description provided for @shuffleOn.
  ///
  /// In de, this message translates to:
  /// **'Zufallswiedergabe an'**
  String get shuffleOn;

  /// No description provided for @songs.
  ///
  /// In de, this message translates to:
  /// **'Songs'**
  String get songs;

  /// No description provided for @sort.
  ///
  /// In de, this message translates to:
  /// **'Sortieren'**
  String get sort;

  /// No description provided for @sortArtist.
  ///
  /// In de, this message translates to:
  /// **'Künstler'**
  String get sortArtist;

  /// No description provided for @sortRecent.
  ///
  /// In de, this message translates to:
  /// **'Zuletzt hinzugefügt'**
  String get sortRecent;

  /// No description provided for @sortTitle.
  ///
  /// In de, this message translates to:
  /// **'Alphabetisch'**
  String get sortTitle;

  /// No description provided for @sourceLocal.
  ///
  /// In de, this message translates to:
  /// **'Offline-Datei'**
  String get sourceLocal;

  /// No description provided for @sourceStream.
  ///
  /// In de, this message translates to:
  /// **'Stream'**
  String get sourceStream;

  /// No description provided for @storageUsed.
  ///
  /// In de, this message translates to:
  /// **'{size} belegt'**
  String storageUsed(String size);

  /// No description provided for @streamingQuality.
  ///
  /// In de, this message translates to:
  /// **'Streamingqualität'**
  String get streamingQuality;

  /// No description provided for @trackCount.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =0{Keine Songs} =1{1 Song} other{{count} Songs}}'**
  String trackCount(int count);

  /// No description provided for @typeAlbum.
  ///
  /// In de, this message translates to:
  /// **'Album'**
  String get typeAlbum;

  /// No description provided for @typeAlbums.
  ///
  /// In de, this message translates to:
  /// **'Alben'**
  String get typeAlbums;

  /// No description provided for @typeEp.
  ///
  /// In de, this message translates to:
  /// **'EP'**
  String get typeEp;

  /// No description provided for @typeEps.
  ///
  /// In de, this message translates to:
  /// **'EPs'**
  String get typeEps;

  /// No description provided for @typeSingle.
  ///
  /// In de, this message translates to:
  /// **'Single'**
  String get typeSingle;

  /// No description provided for @typeSingles.
  ///
  /// In de, this message translates to:
  /// **'Singles'**
  String get typeSingles;

  /// No description provided for @unavailable.
  ///
  /// In de, this message translates to:
  /// **'Nicht verfügbar'**
  String get unavailable;

  /// No description provided for @upNext.
  ///
  /// In de, this message translates to:
  /// **'Als Nächstes'**
  String get upNext;

  /// No description provided for @username.
  ///
  /// In de, this message translates to:
  /// **'Anmeldename'**
  String get username;

  /// No description provided for @usernameRules.
  ///
  /// In de, this message translates to:
  /// **'3–32 Zeichen: Buchstaben, Ziffern, Punkt, Unter- und Bindestrich.'**
  String get usernameRules;

  /// No description provided for @yourPlaylists.
  ///
  /// In de, this message translates to:
  /// **'Deine Playlists'**
  String get yourPlaylists;

  /// No description provided for @deleteAccount.
  ///
  /// In de, this message translates to:
  /// **'Konto löschen'**
  String get deleteAccount;

  /// No description provided for @deleteAccountSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Konto und persönliche Daten endgültig entfernen'**
  String get deleteAccountSubtitle;

  /// No description provided for @deleteAccountTitle.
  ///
  /// In de, this message translates to:
  /// **'Konto endgültig löschen?'**
  String get deleteAccountTitle;

  /// No description provided for @deleteAccountMessage.
  ///
  /// In de, this message translates to:
  /// **'Dein Konto wird auf dem Server gelöscht – mit allen Playlists, Lieblingssongs, gespeicherten Veröffentlichungen, gefolgten Künstlern, dem Hörverlauf und deinen Einstellungen. Auch deine Downloads auf diesem Gerät werden entfernt. Die Musikbibliothek selbst bleibt erhalten. Das kann nicht rückgängig gemacht werden.'**
  String get deleteAccountMessage;

  /// No description provided for @deleteAccountPassword.
  ///
  /// In de, this message translates to:
  /// **'Passwort zur Bestätigung'**
  String get deleteAccountPassword;

  /// No description provided for @deleteAccountConfirm.
  ///
  /// In de, this message translates to:
  /// **'Endgültig löschen'**
  String get deleteAccountConfirm;

  /// No description provided for @deleteAccountBusy.
  ///
  /// In de, this message translates to:
  /// **'Wird gelöscht …'**
  String get deleteAccountBusy;

  /// No description provided for @adminDeleteUser.
  ///
  /// In de, this message translates to:
  /// **'Konto löschen'**
  String get adminDeleteUser;

  /// No description provided for @adminDeleteUserTitle.
  ///
  /// In de, this message translates to:
  /// **'Konto löschen?'**
  String get adminDeleteUserTitle;

  /// No description provided for @adminDeleteUserMessage.
  ///
  /// In de, this message translates to:
  /// **'Konto „{name}“ endgültig löschen? Playlists, Lieblingssongs, Hörverlauf und Einstellungen dieses Kontos werden entfernt. Die Musikbibliothek bleibt erhalten. Das kann nicht rückgängig gemacht werden.'**
  String adminDeleteUserMessage(String name);

  /// No description provided for @setupTitle.
  ///
  /// In de, this message translates to:
  /// **'Konto einrichten'**
  String get setupTitle;

  /// No description provided for @setupStep.
  ///
  /// In de, this message translates to:
  /// **'Schritt {current} von {total}'**
  String setupStep(int current, int total);

  /// No description provided for @setupPasswordTitle.
  ///
  /// In de, this message translates to:
  /// **'Willkommen bei Demonify'**
  String get setupPasswordTitle;

  /// No description provided for @setupPasswordIntro.
  ///
  /// In de, this message translates to:
  /// **'Dein Konto wurde mit einem Startpasswort angelegt. Lege deinen Anzeigenamen und ein eigenes Passwort fest – das Startpasswort ist danach ungültig.'**
  String get setupPasswordIntro;

  /// No description provided for @displayName.
  ///
  /// In de, this message translates to:
  /// **'Anzeigename'**
  String get displayName;

  /// No description provided for @displayNameHelp.
  ///
  /// In de, this message translates to:
  /// **'So wirst du in Demonify angezeigt. Angemeldet wird weiter mit dem Anmeldenamen.'**
  String get displayNameHelp;

  /// No description provided for @displayNameMissing.
  ///
  /// In de, this message translates to:
  /// **'Noch nicht festgelegt – tippen zum Ergänzen'**
  String get displayNameMissing;

  /// No description provided for @setupStartPassword.
  ///
  /// In de, this message translates to:
  /// **'Startpasswort'**
  String get setupStartPassword;

  /// No description provided for @newPassword.
  ///
  /// In de, this message translates to:
  /// **'Neues Passwort (mind. 10 Zeichen)'**
  String get newPassword;

  /// No description provided for @setupContinue.
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get setupContinue;

  /// No description provided for @setupEmailTitle.
  ///
  /// In de, this message translates to:
  /// **'E-Mail-Adresse bestätigen'**
  String get setupEmailTitle;

  /// No description provided for @setupEmailIntro.
  ///
  /// In de, this message translates to:
  /// **'Mit einer bestätigten E-Mail-Adresse kannst du dich auch per E-Mail anmelden und dein Passwort selbst zurücksetzen, falls du es vergisst.'**
  String get setupEmailIntro;

  /// No description provided for @email.
  ///
  /// In de, this message translates to:
  /// **'E-Mail-Adresse'**
  String get email;

  /// No description provided for @emailNew.
  ///
  /// In de, this message translates to:
  /// **'Neue E-Mail-Adresse'**
  String get emailNew;

  /// No description provided for @emailInvalid.
  ///
  /// In de, this message translates to:
  /// **'Bitte eine gültige E-Mail-Adresse eingeben.'**
  String get emailInvalid;

  /// No description provided for @emailNone.
  ///
  /// In de, this message translates to:
  /// **'Keine bestätigte Adresse'**
  String get emailNone;

  /// No description provided for @emailPending.
  ///
  /// In de, this message translates to:
  /// **'Wartet auf Bestätigung: {email}'**
  String emailPending(String email);

  /// No description provided for @passwordConfirmLabel.
  ///
  /// In de, this message translates to:
  /// **'Aktuelles Passwort zur Bestätigung'**
  String get passwordConfirmLabel;

  /// No description provided for @emailSendLink.
  ///
  /// In de, this message translates to:
  /// **'Bestätigungslink senden'**
  String get emailSendLink;

  /// No description provided for @emailLinkSent.
  ///
  /// In de, this message translates to:
  /// **'Wir haben einen Bestätigungslink an {email} gesendet. Öffne ihn – gern auch auf einem anderen Gerät – und tippe danach auf „Ich habe bestätigt“.'**
  String emailLinkSent(String email);

  /// No description provided for @emailIConfirmed.
  ///
  /// In de, this message translates to:
  /// **'Ich habe bestätigt'**
  String get emailIConfirmed;

  /// No description provided for @emailNotYetConfirmed.
  ///
  /// In de, this message translates to:
  /// **'Die Adresse ist noch nicht bestätigt. Bitte öffne den Link in der Mail (auch im Spam-Ordner nachsehen).'**
  String get emailNotYetConfirmed;

  /// No description provided for @emailResend.
  ///
  /// In de, this message translates to:
  /// **'Link erneut senden'**
  String get emailResend;

  /// No description provided for @emailLinkResent.
  ///
  /// In de, this message translates to:
  /// **'Neuer Link gesendet. Ältere Links sind damit ungültig.'**
  String get emailLinkResent;

  /// No description provided for @emailResendOrChange.
  ///
  /// In de, this message translates to:
  /// **'Erneut senden oder andere Adresse'**
  String get emailResendOrChange;

  /// No description provided for @emailChangeAddress.
  ///
  /// In de, this message translates to:
  /// **'Andere Adresse verwenden'**
  String get emailChangeAddress;

  /// No description provided for @emailChangeTitle.
  ///
  /// In de, this message translates to:
  /// **'E-Mail-Adresse ändern'**
  String get emailChangeTitle;

  /// No description provided for @emailChangeIntro.
  ///
  /// In de, this message translates to:
  /// **'Die neue Adresse wird erst aktiv, wenn du den Link in der Bestätigungsmail öffnest. Bis dahin bleibt die bisherige Adresse gültig.'**
  String get emailChangeIntro;

  /// No description provided for @loginIdentifier.
  ///
  /// In de, this message translates to:
  /// **'Anmeldename oder E-Mail'**
  String get loginIdentifier;

  /// No description provided for @forgotPassword.
  ///
  /// In de, this message translates to:
  /// **'Passwort vergessen?'**
  String get forgotPassword;

  /// No description provided for @forgotIntro.
  ///
  /// In de, this message translates to:
  /// **'Gib deinen Anmeldenamen oder deine bestätigte E-Mail-Adresse ein. Wir senden dir einen Link, mit dem du ein neues Passwort festlegen kannst.'**
  String get forgotIntro;

  /// No description provided for @forgotSend.
  ///
  /// In de, this message translates to:
  /// **'Link senden'**
  String get forgotSend;

  /// No description provided for @forgotSending.
  ///
  /// In de, this message translates to:
  /// **'Wird gesendet …'**
  String get forgotSending;

  /// No description provided for @forgotFallback.
  ///
  /// In de, this message translates to:
  /// **'Keine bestätigte E-Mail-Adresse oder kein Zugriff mehr darauf? Dann kann ein Administrator dein Passwort zurücksetzen.'**
  String get forgotFallback;

  /// No description provided for @backToLogin.
  ///
  /// In de, this message translates to:
  /// **'Zurück zur Anmeldung'**
  String get backToLogin;

  /// No description provided for @inviteEmailHelp.
  ///
  /// In de, this message translates to:
  /// **'Du erhältst einen Link zur Bestätigung.'**
  String get inviteEmailHelp;

  /// No description provided for @libraryAlbums.
  ///
  /// In de, this message translates to:
  /// **'Alben'**
  String get libraryAlbums;

  /// No description provided for @libraryCatalog.
  ///
  /// In de, this message translates to:
  /// **'Gesamter Katalog'**
  String get libraryCatalog;

  /// No description provided for @libraryClearFilter.
  ///
  /// In de, this message translates to:
  /// **'Filter aufheben'**
  String get libraryClearFilter;

  /// No description provided for @libraryEmptyAll.
  ///
  /// In de, this message translates to:
  /// **'Deine Bibliothek ist noch leer'**
  String get libraryEmptyAll;

  /// No description provided for @libraryEmptyAllHint.
  ///
  /// In de, this message translates to:
  /// **'Erstelle Playlists, speichere Alben oder folge Künstlern – alles erscheint hier gemeinsam.'**
  String get libraryEmptyAllHint;

  /// No description provided for @libraryEmptyPlaylists.
  ///
  /// In de, this message translates to:
  /// **'Noch keine eigenen Playlists'**
  String get libraryEmptyPlaylists;

  /// No description provided for @libraryEmptyAlbums.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Alben gespeichert'**
  String get libraryEmptyAlbums;

  /// No description provided for @libraryEmptyAlbumsHint.
  ///
  /// In de, this message translates to:
  /// **'Tippe auf einer Album-Seite auf „Speichern“, um es hier zu sehen.'**
  String get libraryEmptyAlbumsHint;

  /// No description provided for @libraryEmptyArtists.
  ///
  /// In de, this message translates to:
  /// **'Du folgst noch keinen Künstlern'**
  String get libraryEmptyArtists;

  /// No description provided for @libraryEmptyArtistsHint.
  ///
  /// In de, this message translates to:
  /// **'Tippe auf einer Künstlerseite auf „Folgen“.'**
  String get libraryEmptyArtistsHint;

  /// No description provided for @artist.
  ///
  /// In de, this message translates to:
  /// **'Künstler'**
  String get artist;
}

class _SDelegate extends LocalizationsDelegate<S> {
  const _SDelegate();

  @override
  Future<S> load(Locale locale) {
    return SynchronousFuture<S>(lookupS(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de'].contains(locale.languageCode);

  @override
  bool shouldReload(_SDelegate old) => false;
}

S lookupS(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return SDe();
  }

  throw FlutterError(
    'S.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

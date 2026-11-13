// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class SDe extends S {
  SDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Demonify';

  @override
  String get add => 'Hinzufügen';

  @override
  String get addToPlaylist => 'Zur Playlist hinzufügen';

  @override
  String get addToQueue => 'Zur Warteschlange hinzufügen';

  @override
  String get addedToQueue => 'Zur Warteschlange hinzugefügt.';

  @override
  String get adminAddArtist => 'Künstler hinzufügen …';

  @override
  String get adminAddFeature => 'Feature hinzufügen …';

  @override
  String adminArtistExists(String name) {
    return '„$name“ existiert bereits (gleicher Name nach Normalisierung).';
  }

  @override
  String get adminArtistName => 'Künstlername';

  @override
  String get adminArtistSearch => 'Künstler suchen …';

  @override
  String get adminArtists => 'Künstler';

  @override
  String get adminArtistsSub => 'Anlegen, umbenennen, Profilbilder';

  @override
  String get adminArtistsTitle => 'Künstlerverwaltung';

  @override
  String get adminChangeCover => 'Cover ersetzen';

  @override
  String get adminChooseAudio => 'Audiodateien auswählen';

  @override
  String get adminChooseCover => 'Cover auswählen';

  @override
  String get adminCommitting => 'Wird abgelegt …';

  @override
  String get adminConfirmHint =>
      'Der Server prüft die Dateien, legt Künstler-, Typ- und Veröffentlichungsordner automatisch an und überschreibt keine vorhandenen Dateien.';

  @override
  String get adminConfirmUpload => 'Upload bestätigen';

  @override
  String get adminCreate => 'Anlegen';

  @override
  String get adminCreateArtist => 'Neuen Künstler erstellen';

  @override
  String adminCreateArtistNamed(String name) {
    return 'Neuen Künstler erstellen: „$name“';
  }

  @override
  String get adminCreateInvite => 'Einladung erstellen';

  @override
  String get adminCreateUser => 'Benutzer anlegen';

  @override
  String get adminDisable => 'Sperren';

  @override
  String get adminDisabled => 'gesperrt';

  @override
  String get adminDisc => 'Disc';

  @override
  String get adminEnable => 'Entsperren';

  @override
  String get adminFeatures => 'Features';

  @override
  String get adminGenre => 'Genre';

  @override
  String get adminInviteCreated =>
      'Einladung erstellt (Link wird nur jetzt angezeigt)';

  @override
  String get adminInvites => 'Einladungen';

  @override
  String get adminIssues => 'Offene Probleme';

  @override
  String get adminJobs => 'Aufträge & Probleme';

  @override
  String get adminJobsSub => 'Bibliotheksscan, Fortschritt, Fehler';

  @override
  String get adminMakeAdmin => 'Zum Admin machen';

  @override
  String get adminMakeUser => 'Zum Benutzer machen';

  @override
  String adminNewRelease(String type) {
    return 'Neue Veröffentlichung ($type) anlegen';
  }

  @override
  String get adminNoArtistFound => 'Keine passenden Künstler gefunden.';

  @override
  String get adminOpenRelease => 'Veröffentlichung öffnen';

  @override
  String get adminOwnCover => 'eigenes Cover';

  @override
  String adminReleaseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Veröffentlichungen',
      one: '1 Veröffentlichung',
    );
    return '$_temp0';
  }

  @override
  String get adminReleaseCover => 'Veröffentlichungscover';

  @override
  String get adminReleaseSearch => 'Veröffentlichung suchen …';

  @override
  String get adminReleaseTitle => 'Titel';

  @override
  String get adminReleasesSub => 'Metadaten, Cover, Trackreihenfolge';

  @override
  String get adminReleasesTitle => 'Veröffentlichungen';

  @override
  String get adminRemoveArtistImage => 'Profilbild entfernen';

  @override
  String get adminRemoveSongCover =>
      'Songcover entfernen (Veröffentlichungscover verwenden)';

  @override
  String get adminReplaceArtistImage => 'Profilbild ersetzen';

  @override
  String get adminReplaceSongCover => 'Songcover ersetzen';

  @override
  String get adminResolve => 'Als erledigt markieren';

  @override
  String get adminReviewHint =>
      'Titel, Künstler, Features, Nummern, Reihenfolge und individuelle Songcover prüfen. Ohne eigenes Songcover wird das Veröffentlichungscover verwendet.';

  @override
  String get adminRevoke => 'Widerrufen';

  @override
  String get adminRevokeSessions => 'Alle Sitzungen beenden';

  @override
  String get adminSaveOrder => 'Reihenfolge speichern';

  @override
  String adminSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Sitzungen',
      one: '1 Sitzung',
    );
    return '$_temp0';
  }

  @override
  String get adminSimilarArtists =>
      'Ähnliche Namen (werden nicht zusammengeführt):';

  @override
  String get adminSongCover => 'Songcover zuordnen';

  @override
  String get adminStartPassword => 'Startpasswort (mind. 10 Zeichen)';

  @override
  String get adminStartScan => 'Bibliotheksscan';

  @override
  String get adminStepArtist => 'Künstler';

  @override
  String get adminStepArtistHint =>
      'Vorhandenen Künstler auswählen oder neuen anlegen – Vorschläge erscheinen ab dem ersten Buchstaben.';

  @override
  String get adminStepConfirm => 'Bestätigen';

  @override
  String get adminStepFiles => 'Audiodateien';

  @override
  String get adminStepMeta => 'Metadaten & Cover';

  @override
  String get adminStepRelease => 'Veröffentlichung';

  @override
  String get adminStepReview => 'Prüfen';

  @override
  String get adminStepType => 'Typ';

  @override
  String get adminTitle => 'Titel';

  @override
  String adminTrackArtistMissing(int n) {
    return 'Track $n: mindestens ein Künstler nötig.';
  }

  @override
  String get adminTrackNo => 'Nr.';

  @override
  String adminTrackNumberDuplicate(int disc, int number) {
    return 'Disc $disc, Track $number ist doppelt vergeben.';
  }

  @override
  String adminTrackTitleMissing(int n) {
    return 'Track $n: Titel fehlt.';
  }

  @override
  String get adminTracks => 'Tracks';

  @override
  String get adminType => 'Typ';

  @override
  String get adminUnavailable => 'Nicht verfügbare Dateien';

  @override
  String get adminUpload => 'Musik hochladen';

  @override
  String get adminUploadAnother => 'Weiteren Upload starten';

  @override
  String get adminUploadArtistImage => 'Profilbild hochladen';

  @override
  String get adminUploadDone => 'Upload abgeschlossen';

  @override
  String get adminUploadSub =>
      'Künstler, Veröffentlichung, Dateien – Ablage automatisch';

  @override
  String get adminUploading => 'Wird hochgeladen …';

  @override
  String get adminUsers => 'Benutzer';

  @override
  String get adminUsersSub => 'Benutzer, Rollen, Einladungen';

  @override
  String get adminValidated => 'Geprüft ✓';

  @override
  String get adminValidating => 'Wird geprüft …';

  @override
  String get adminWaitingUploads =>
      'Warte auf Abschluss und Prüfung aller Uploads …';

  @override
  String get adminYear => 'Jahr';

  @override
  String get allSongs => 'Alle Songs';

  @override
  String get appVersion => 'App-Version';

  @override
  String get appearsOn => 'Enthalten in';

  @override
  String get artistLabel => 'Künstler';

  @override
  String get artists => 'Künstler';

  @override
  String get back => 'Zurück';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get cancelled => 'Abgebrochen';

  @override
  String get change => 'Ändern';

  @override
  String get clear => 'Leeren';

  @override
  String get clearQueue => 'Leeren';

  @override
  String get close => 'Schließen';

  @override
  String get copy => 'Kopieren';

  @override
  String get delete => 'Löschen';

  @override
  String discNumber(int n) {
    return 'Disc $n';
  }

  @override
  String get displayNameOptional => 'Anzeigename (optional)';

  @override
  String get done => 'Fertig';

  @override
  String get download => 'Herunterladen';

  @override
  String get downloadCollections => 'Veröffentlichungen & Playlists';

  @override
  String get downloadFailed => 'Fehlgeschlagen';

  @override
  String get downloadQuality => 'Downloadqualität';

  @override
  String get downloadQueued => 'Wartet …';

  @override
  String get downloading => 'Wird heruntergeladen …';

  @override
  String get downloads => 'Downloads';

  @override
  String get downloadsEmpty => 'Noch keine Downloads';

  @override
  String get downloadsEmptyHint =>
      'Lade Songs, Veröffentlichungen oder Playlists herunter, um sie ohne Internet zu hören.';

  @override
  String get downloadsInProgress => 'In Bearbeitung';

  @override
  String get downloadsRemoveAll => 'Alle Downloads löschen';

  @override
  String get downloadsRemoveAllConfirm =>
      'Alle heruntergeladenen Dateien dieses Kontos werden von diesem Gerät gelöscht.';

  @override
  String get downloadsRetryFailed => 'Fehlgeschlagene wiederholen';

  @override
  String get downloadsServerNote =>
      'Hinweis: Heruntergeladene Dateien liegen im privaten App-Speicher dieses Kontos. Wird ein Konto später gesperrt oder ein Song entfernt, bleiben bereits geladene Dateien bis zur nächsten Anmeldung/Abmeldung technisch auf dem Gerät erhalten.';

  @override
  String get eqActiveHint => 'Wirkt auf Streaming und Offline-Wiedergabe.';

  @override
  String get eqEnabled => 'Equalizer';

  @override
  String get eqHeadroom => 'Automatischer Headroom';

  @override
  String eqHeadroomHint(String db) {
    return 'Senkt die Gesamtlautstärke um die stärkste Anhebung, um Übersteuerung zu vermeiden (aktuell $db dB).';
  }

  @override
  String get eqInactiveHint => 'Aus – Wiedergabe unverändert.';

  @override
  String get eqInfoAirplay =>
      'AirPlay und Bluetooth: Der Klang wird auf diesem Gerät berechnet und dann übertragen – der Equalizer wirkt also auch dort.';

  @override
  String get eqInfoBody =>
      '10 Bänder von 31 Hz bis 16 kHz, je −12 bis +12 dB. Die Dateien selbst werden nie verändert; Einstellungen gelten für dieses Konto auf diesem Gerät.';

  @override
  String get eqInfoCast =>
      'Bluetooth und Kopfhörer: Der Klang wird auf diesem Gerät berechnet – der Equalizer wirkt. Bei künftigem Casting (Wiedergabe direkt auf dem Zielgerät) wirkt er nicht.';

  @override
  String get eqInfoTitle => 'So funktioniert der Equalizer';

  @override
  String get eqPreamp => 'Vorverstärkung';

  @override
  String get eqPresets => 'Voreinstellungen';

  @override
  String get eqUnavailable =>
      'Die Audioengine hat den Equalizer-Filter auf diesem Gerät nicht angenommen. Die Wiedergabe funktioniert weiterhin, aber ohne Klangverarbeitung.';

  @override
  String get equalizer => 'Equalizer';

  @override
  String get error => 'Fehler';

  @override
  String get errorGenericTitle => 'Etwas ist schiefgelaufen';

  @override
  String get errorNetworkTitle => 'Keine Verbindung';

  @override
  String get favoriteAdd => 'Zu Lieblingssongs hinzufügen';

  @override
  String get favoriteRemove => 'Aus Lieblingssongs entfernen';

  @override
  String get favorites => 'Lieblingssongs';

  @override
  String get favoritesEmpty => 'Noch keine Lieblingssongs';

  @override
  String get favoritesEmptyHint =>
      'Tippe auf das Herz, um Songs hier zu sammeln.';

  @override
  String get fieldRequired => 'Pflichtfeld';

  @override
  String get follow => 'Folgen';

  @override
  String get followedArtists => 'Gefolgte Künstler';

  @override
  String get following => 'Folge ich';

  @override
  String goToArtistNamed(String name) {
    return 'Zu $name';
  }

  @override
  String get goToRelease => 'Zur Veröffentlichung';

  @override
  String get greetingDay => 'Hallo';

  @override
  String get greetingEvening => 'Guten Abend';

  @override
  String get greetingMorning => 'Guten Morgen';

  @override
  String greetingName(String greeting, String name) {
    return '$greeting, $name';
  }

  @override
  String get hidePassword => 'Passwort verbergen';

  @override
  String get homeEmptyMessage =>
      'Sobald Musik hochgeladen oder gescannt wurde, erscheint sie hier.';

  @override
  String get homeEmptyTitle => 'Noch keine Musik in der Bibliothek';

  @override
  String get inviteCode => 'Einladungscode oder -link';

  @override
  String get inviteRedeem => 'Einladung einlösen';

  @override
  String get inviteSubmit => 'Konto erstellen';

  @override
  String get inviteSuccess => 'Konto erstellt – du kannst dich jetzt anmelden.';

  @override
  String get jobCleanup => 'Upload-Bereinigung';

  @override
  String get jobScan => 'Bibliotheksscan';

  @override
  String get jobTranscode => 'Transkodierung';

  @override
  String get libraryAll => 'Alle';

  @override
  String get libraryEmpty => 'Hier ist noch nichts.';

  @override
  String get libraryFollowed => 'Gefolgt';

  @override
  String get librarySaved => 'Gespeichert';

  @override
  String get login => 'Anmelden';

  @override
  String get loginChangeServer => 'Serveradresse ändern';

  @override
  String get loginSubtitle => 'Deine private Musikplattform';

  @override
  String get logout => 'Abmelden';

  @override
  String get logoutDeleteDownloads =>
      'Downloads dieses Kontos von diesem Gerät löschen';

  @override
  String get logoutMessage =>
      'Du wirst auf diesem Gerät abgemeldet. Die Sitzung wird auch auf dem Server beendet.';

  @override
  String get logoutTitle => 'Abmelden?';

  @override
  String get manageDownloads => 'Downloads verwalten';

  @override
  String get moreActions => 'Weitere Aktionen';

  @override
  String get navAdmin => 'Verwaltung';

  @override
  String get navHome => 'Start';

  @override
  String get navLibrary => 'Bibliothek';

  @override
  String get navSearch => 'Suche';

  @override
  String get navSettings => 'Einstellungen';

  @override
  String get newReleases => 'Neu hinzugefügt';

  @override
  String get next => 'Weiter';

  @override
  String get nothingPlaying => 'Nichts in der Wiedergabe';

  @override
  String get nowPlaying => 'Wird gespielt';

  @override
  String get off => 'Aus';

  @override
  String get offlineBanner =>
      'Offline – nur heruntergeladene Musik ist verfügbar.';

  @override
  String get on => 'An';

  @override
  String get openPlayer => 'Player öffnen';

  @override
  String get password => 'Passwort';

  @override
  String get passwordMismatch => 'Die Passwörter stimmen nicht überein.';

  @override
  String get passwordRepeat => 'Passwort wiederholen';

  @override
  String get passwordTooShort => 'Mindestens 10 Zeichen.';

  @override
  String get pause => 'Pause';

  @override
  String get play => 'Abspielen';

  @override
  String get playNext => 'Als Nächstes spielen';

  @override
  String get playlist => 'Playlist';

  @override
  String playlistAdded(String name) {
    return 'Zu „$name“ hinzugefügt.';
  }

  @override
  String get playlistCreate => 'Erstellen';

  @override
  String get playlistDelete => 'Playlist löschen';

  @override
  String playlistDeleteConfirm(String name) {
    return '„$name“ wirklich löschen?';
  }

  @override
  String get playlistEditOrder => 'Reihenfolge bearbeiten';

  @override
  String get playlistEmpty => 'Diese Playlist ist leer';

  @override
  String get playlistEmptyHint =>
      'Füge Songs über das Menü ⋮ eines Songs hinzu.';

  @override
  String get playlistName => 'Name der Playlist';

  @override
  String get playlistNew => 'Neue Playlist';

  @override
  String get playlistRemoveEntry => 'Aus Playlist entfernen';

  @override
  String get playlistRename => 'Umbenennen';

  @override
  String get playlists => 'Playlists';

  @override
  String get popularSongs => 'Beliebte Songs';

  @override
  String get presetBassBoost => 'Bass Boost';

  @override
  String get presetCustom => 'Benutzerdefiniert';

  @override
  String get presetElectronic => 'Elektronisch';

  @override
  String get presetNeutral => 'Neutral';

  @override
  String get presetPop => 'Pop';

  @override
  String get presetRock => 'Rock';

  @override
  String get presetVocal => 'Gesang';

  @override
  String get previous => 'Zurück';

  @override
  String get qualityHigh => 'Hoch (AAC 256 kbit/s)';

  @override
  String get qualityHint =>
      'Transkodierte Stufen werden beim ersten Abruf auf dem Server erzeugt; bis dahin wird das Original geliefert.';

  @override
  String get qualityLow => 'Datensparend (AAC 96 kbit/s)';

  @override
  String get qualityNormal => 'Normal (AAC 160 kbit/s)';

  @override
  String get qualityOriginal => 'Original (verlustfrei, falls vorhanden)';

  @override
  String get queue => 'Warteschlange';

  @override
  String get queueEmpty => 'Die Warteschlange ist leer';

  @override
  String get recentlyPlayed => 'Zuletzt gehört';

  @override
  String get reconnect => 'Verbinden';

  @override
  String get releases => 'Veröffentlichungen';

  @override
  String get remove => 'Entfernen';

  @override
  String get removeDownload => 'Download entfernen';

  @override
  String get removeDownloadConfirm =>
      'Die heruntergeladenen Dateien werden von diesem Gerät gelöscht.';

  @override
  String get removeFromQueue => 'Aus Warteschlange entfernen';

  @override
  String get repeatAll => 'Alle wiederholen';

  @override
  String get repeatOff => 'Wiederholung aus';

  @override
  String get repeatOne => 'Titel wiederholen';

  @override
  String get reset => 'Zurücksetzen';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String get roleAdmin => 'Administrator';

  @override
  String get roleUser => 'Benutzer';

  @override
  String get save => 'Speichern';

  @override
  String get saved => 'Gespeichert';

  @override
  String get searchEmptyMessage =>
      'Suche nach Songs, Künstlern, Veröffentlichungen und deinen Playlists.';

  @override
  String get searchEmptyTitle => 'Was möchtest du hören?';

  @override
  String get searchHint => 'Songs, Künstler, Alben …';

  @override
  String searchNoResults(String query) {
    return 'Keine Ergebnisse für „$query“';
  }

  @override
  String get select => 'Auswählen';

  @override
  String get serverAddress => 'Serveradresse';

  @override
  String get serverAddressHint => 'z. B. demonify.thedemonlord333.me';

  @override
  String get settingsAbout => 'Über';

  @override
  String get settingsAccount => 'Konto';

  @override
  String get settingsPlayback => 'Wiedergabe & Downloads';

  @override
  String get settingsSound => 'Klang';

  @override
  String get showAll => 'Alle anzeigen';

  @override
  String showAllSongs(int count) {
    return 'Alle $count Songs anzeigen';
  }

  @override
  String get showPassword => 'Passwort anzeigen';

  @override
  String get shuffle => 'Zufallswiedergabe';

  @override
  String get shuffleOff => 'Zufallswiedergabe aus';

  @override
  String get shuffleOn => 'Zufallswiedergabe an';

  @override
  String get songs => 'Songs';

  @override
  String get sort => 'Sortieren';

  @override
  String get sortArtist => 'Künstler';

  @override
  String get sortRecent => 'Zuletzt hinzugefügt';

  @override
  String get sortTitle => 'Alphabetisch';

  @override
  String get sourceLocal => 'Offline-Datei';

  @override
  String get sourceStream => 'Stream';

  @override
  String storageUsed(String size) {
    return '$size belegt';
  }

  @override
  String get streamingQuality => 'Streamingqualität';

  @override
  String trackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Songs',
      one: '1 Song',
      zero: 'Keine Songs',
    );
    return '$_temp0';
  }

  @override
  String get typeAlbum => 'Album';

  @override
  String get typeAlbums => 'Alben';

  @override
  String get typeEp => 'EP';

  @override
  String get typeEps => 'EPs';

  @override
  String get typeSingle => 'Single';

  @override
  String get typeSingles => 'Singles';

  @override
  String get unavailable => 'Nicht verfügbar';

  @override
  String get upNext => 'Als Nächstes';

  @override
  String get username => 'Anmeldename';

  @override
  String get usernameRules =>
      '3–32 Zeichen: Buchstaben, Ziffern, Punkt, Unter- und Bindestrich.';

  @override
  String get yourPlaylists => 'Deine Playlists';

  @override
  String get deleteAccount => 'Konto löschen';

  @override
  String get deleteAccountSubtitle =>
      'Konto und persönliche Daten endgültig entfernen';

  @override
  String get deleteAccountTitle => 'Konto endgültig löschen?';

  @override
  String get deleteAccountMessage =>
      'Dein Konto wird auf dem Server gelöscht – mit allen Playlists, Lieblingssongs, gespeicherten Veröffentlichungen, gefolgten Künstlern, dem Hörverlauf und deinen Einstellungen. Auch deine Downloads auf diesem Gerät werden entfernt. Die Musikbibliothek selbst bleibt erhalten. Das kann nicht rückgängig gemacht werden.';

  @override
  String get deleteAccountPassword => 'Passwort zur Bestätigung';

  @override
  String get deleteAccountConfirm => 'Endgültig löschen';

  @override
  String get deleteAccountBusy => 'Wird gelöscht …';

  @override
  String get adminDeleteUser => 'Konto löschen';

  @override
  String get adminDeleteUserTitle => 'Konto löschen?';

  @override
  String adminDeleteUserMessage(String name) {
    return 'Konto „$name“ endgültig löschen? Playlists, Lieblingssongs, Hörverlauf und Einstellungen dieses Kontos werden entfernt. Die Musikbibliothek bleibt erhalten. Das kann nicht rückgängig gemacht werden.';
  }

  @override
  String get setupTitle => 'Konto einrichten';

  @override
  String setupStep(int current, int total) {
    return 'Schritt $current von $total';
  }

  @override
  String get setupPasswordTitle => 'Willkommen bei Demonify';

  @override
  String get setupPasswordIntro =>
      'Dein Konto wurde mit einem Startpasswort angelegt. Lege deinen Anzeigenamen und ein eigenes Passwort fest – das Startpasswort ist danach ungültig.';

  @override
  String get displayName => 'Anzeigename';

  @override
  String get displayNameHelp =>
      'So wirst du in Demonify angezeigt. Angemeldet wird weiter mit dem Anmeldenamen.';

  @override
  String get displayNameMissing =>
      'Noch nicht festgelegt – tippen zum Ergänzen';

  @override
  String get setupStartPassword => 'Startpasswort';

  @override
  String get newPassword => 'Neues Passwort (mind. 10 Zeichen)';

  @override
  String get setupContinue => 'Weiter';

  @override
  String get setupEmailTitle => 'E-Mail-Adresse bestätigen';

  @override
  String get setupEmailIntro =>
      'Mit einer bestätigten E-Mail-Adresse kannst du dich auch per E-Mail anmelden und dein Passwort selbst zurücksetzen, falls du es vergisst.';

  @override
  String get email => 'E-Mail-Adresse';

  @override
  String get emailNew => 'Neue E-Mail-Adresse';

  @override
  String get emailInvalid => 'Bitte eine gültige E-Mail-Adresse eingeben.';

  @override
  String get emailNone => 'Keine bestätigte Adresse';

  @override
  String emailPending(String email) {
    return 'Wartet auf Bestätigung: $email';
  }

  @override
  String get passwordConfirmLabel => 'Aktuelles Passwort zur Bestätigung';

  @override
  String get emailSendLink => 'Bestätigungslink senden';

  @override
  String emailLinkSent(String email) {
    return 'Wir haben einen Bestätigungslink an $email gesendet. Öffne ihn – gern auch auf einem anderen Gerät – und tippe danach auf „Ich habe bestätigt“.';
  }

  @override
  String get emailIConfirmed => 'Ich habe bestätigt';

  @override
  String get emailNotYetConfirmed =>
      'Die Adresse ist noch nicht bestätigt. Bitte öffne den Link in der Mail (auch im Spam-Ordner nachsehen).';

  @override
  String get emailResend => 'Link erneut senden';

  @override
  String get emailLinkResent =>
      'Neuer Link gesendet. Ältere Links sind damit ungültig.';

  @override
  String get emailResendOrChange => 'Erneut senden oder andere Adresse';

  @override
  String get emailChangeAddress => 'Andere Adresse verwenden';

  @override
  String get emailChangeTitle => 'E-Mail-Adresse ändern';

  @override
  String get emailChangeIntro =>
      'Die neue Adresse wird erst aktiv, wenn du den Link in der Bestätigungsmail öffnest. Bis dahin bleibt die bisherige Adresse gültig.';

  @override
  String get loginIdentifier => 'Anmeldename oder E-Mail';

  @override
  String get forgotPassword => 'Passwort vergessen?';

  @override
  String get forgotIntro =>
      'Gib deinen Anmeldenamen oder deine bestätigte E-Mail-Adresse ein. Wir senden dir einen Link, mit dem du ein neues Passwort festlegen kannst.';

  @override
  String get forgotSend => 'Link senden';

  @override
  String get forgotSending => 'Wird gesendet …';

  @override
  String get forgotFallback =>
      'Keine bestätigte E-Mail-Adresse oder kein Zugriff mehr darauf? Dann kann ein Administrator dein Passwort zurücksetzen.';

  @override
  String get backToLogin => 'Zurück zur Anmeldung';

  @override
  String get inviteEmailHelp => 'Du erhältst einen Link zur Bestätigung.';
}

classdef BIOPACDevice < handle
    properties(GetAccess = 'public', SetAccess = 'private')
        % Folder where the library and the header resides
        lib_path = 'C:\BHAPI\';
        lib_handle = 'mpdev';
        
        % Channel mask for setAcqChannels()
        channel_mask;

        % Some enumerations from mpdev.h
        enum_info;

        % Default sample rate is 200Hz
        sample_rate = 200;

        % Default preset is EEG, single channel
        % Length of this cell array also defines the channel number
        ch_presets = {'a22'};
        nb_channels;
        
        % XML preset file is by default in the same directory
        xml_presets = 'PresetFiles\channelpresets.xml';
        
        % Device type and connection method
        mp_type;
        mp_method;
    end
    
    methods
        function obj = BIOPACDevice(lib_path, mp_type, mp_method, sample_rate, ch_presets)
            % Call prototype functions to get the enumerations
            [~, ~, obj.enum_info, ~] = mpdevproto();

            % Constructor
            if nargin > 0
                obj.lib_path = lib_path;
                obj.sample_rate = sample_rate;
                obj.nb_channels = length(ch_presets);
                obj.ch_presets = ch_presets;
                
                switch lower(mp_type)
                    case 'mp150'
                        obj.mp_type = obj.enum_info.MP_TYPE.MP150;
                        obj.channel_mask = zeros(1, 16);
                    case 'mp35'
                        obj.mp_type = obj.enum_info.MP_TYPE.MP35;
                        obj.channel_mask = zeros(1, 4);
                    case 'mp36'
                        obj.mp_type = obj.enum_info.MP_TYPE.MP36;
                        obj.channel_mask = zeros(1, 4);
                end
                
                switch lower(mp_method)
                    case 'usb'
                        obj.mp_method = obj.enum_info.MP_COM_TYPE.MPUSB;
                    case 'udp'
                        obj.mp_method = obj.enum_info.MP_COM_TYPE.MPUDP;
                end
                
                % Init channel mask for setAcqChannels()
                for i = 1:length(ch_presets)
                    obj.channel_mask(i) = 1;
                end
            end
            
            % Load the library using prototype file
            loadlibrary(strcat(obj.lib_path, 'mpdev.dll'), @mpdevproto);
            
            % Init the device
            obj.disconnect();
            obj.connect();
            obj.loadXMLPresetFile();
            obj.configureChannelsByPresetID();
            obj.setSampleRate();
            obj.setAcquisitionChannels();
            
            % Read once to clean gain fluctuations
            obj.startAcquisition();
            obj.readAndStopAcquisition(obj.sample_rate);
        end
        
        function delete(obj)
            % This is called when you issue a 'clear' command in MATLAB
            obj.disconnect();
            obj.unload();
        end

        function unload(obj)
            if libisloaded(obj.lib_handle)
                unloadlibrary(obj.lib_handle)
            end
        end
        
        function retval = connect(obj)
            retval = calllib(obj.lib_handle, 'connectMPDev', obj.mp_type, obj.mp_method, 'auto');
        end

        function retval = disconnect(obj)
            retval = 'MPNOTCON';
            if strcmp(obj.status(), 'MPREADY')
                retval = calllib(obj.lib_handle, 'disconnectMPDev');
            end
        end
        
        function retval = configureChannelsByPresetID(obj)
            for i = 1:length(obj.ch_presets)
                retval = calllib(obj.lib_handle, 'configChannelByPresetID', i-1, obj.ch_presets{i});
            end
        end
        
        function retval = loadXMLPresetFile(obj)
            retval = calllib(obj.lib_handle, 'loadXMLPresetFile', obj.xml_presets);
        end
        
        function retval = status(obj)
            retval = calllib(obj.lib_handle, 'getStatusMPDev');
        end
        
        function retval = setAcquisitionChannels(obj)
            retval = calllib(obj.lib_handle, 'setAcqChannels', obj.channel_mask);
        end

        function retval = setSampleRate(obj)
            retval = calllib(obj.lib_handle, 'setSampleRate', double(1000/obj.sample_rate));
        end
        
        function retval = startAcquisition(obj)
            obj.startMpAcqDaemon();
            retval = calllib(obj.lib_handle, 'startAcquisition');
        end
        
        function retval = stopAcquisition(obj)
            retval = calllib(obj.lib_handle, 'stopAcquisition');
        end
        
        function [total_read, buff] = readOneShot(obj, samples_to_fetch)
            % How many data is read?
            total_read = 0;
            
            % Temporary buffer
            buff(1:samples_to_fetch) = double(0);
            
            % Read the requested samples
            [~, buff, total_read] = calllib(obj.lib_handle, ...
                    'receiveMPData', buff, ...
                    samples_to_fetch, total_read);
        end
        
        function buff = readAndStopAcquisition(obj, samples_to_fetch)
            total_read = 0;
            
            % Place to hold each channel's data
            buff = zeros(obj.nb_channels, samples_to_fetch);
            
            % Collect 1 second worth of data points per iteration
            to_read = obj.sample_rate * obj.nb_channels;
            
            % Multiply the number of samples by the number of channels
            samples_to_fetch = samples_to_fetch * obj.nb_channels;
            
            % Initialize the correct amount of data
            temp_buffer(1:to_read) = double(0);
            offset = 1;
            
            while(samples_to_fetch > 0)
                if to_read > samples_to_fetch
                    to_read = samples_to_fetch;
                end

                [retval, temp_buffer, total_read] = calllib(obj.lib_handle, ...
                    'receiveMPData', temp_buffer, to_read, total_read);
                
                if ~strcmp(retval, 'MPSUCCESS')
                    fprintf(1, 'Failed to receive MP data (Error: %s)\n', retval);
                    fprintf(1, 'MPDaemonLastError: %s\n', obj.getMPDaemonLastError());
                    obj.stopAcquisition();
                    obj.disconnect();
                    return
                else
                    % Place interleaved data into each channel's data in buff
                    for n_ch = 1:obj.nb_channels
                        buff(n_ch, offset:offset + total_read/obj.nb_channels - 1) = temp_buffer(n_ch:obj.nb_channels:total_read);
                    end
                end
                
                % Compute new values
                offset = offset + total_read/obj.nb_channels;
                samples_to_fetch = samples_to_fetch - total_read;
            end

            % Stop acquisition
            obj.stopAcquisition();
        end
        
        function retval = startMpAcqDaemon(obj)
            retval = calllib(obj.lib_handle, 'startMPAcqDaemon');
        end
        
        function retval = getMPDaemonLastError(obj)
            retval = calllib(obj.lib_handle, 'getMPDaemonLastError');
        end
    end
end
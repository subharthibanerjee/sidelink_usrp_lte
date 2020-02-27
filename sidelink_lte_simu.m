%% __author__       =  Subharthi Banerjee
%  __description__  =  "This code is used to emulate USRP-B210 based LTE 
%                       sidelink. This work has been done to simulate and 
%                       emulate at the same time. "
%  __dated__        =   02/26/2020

%% ---------------- simulation -------------------------

clear
close all
clc
fprintf("\n\t\t\t************************************************************\n");
fprintf("\n\t\t\t*          PROXIMITY SERVICES SIMULATION                   *\n")
fprintf("\n\t\t\t************************************************************\n");
fprintf("\nCode running at %s\n", datestr(now,'HH:MM:SS.FFF'));

fprint("\nChecking if USRP works .....\n");

%% function to check USRP
checkUSRP();
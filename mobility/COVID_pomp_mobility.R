# for fitting E0 added E_init parameter that would need to be discarded
# define the changes for a time step forward
sir_step_mobility <- Csnippet("
                     // adjust betat for social distancing interventions
                     double betat;
                     betat = beta0*exp(log(beta_min)*sip_prop);
                     //(mobility*(1 - beta_min) + beta_min);

                     // if import rate is above zero, draw importations, assuming they are perfectly balanced with departures of susceptible individuals
                     double import = 0;
                     if(import_rate > 0){
                      import = fmin(rpois(import_rate*dt), S);
                     }
                     // tracking of total imported, removing them them from susceptibles
                     import_total += import;
                     S -= import;
                     double iso_m = 1;
                     double iso_s = 1;
                     
                     // calculate transition numbers
                     double dSE = rbinom(S, 1-exp(-betat*(Ca*Ia/N + Cp*Ip/N + iso_m*Cm*Im/N + iso_s*Cs*Is/N)*dt)); 
                     double rateE[2];
                     double dE_all[2];
                     rateE[0] = alpha*gamma; // going to asymtomatic
                     rateE[1] = (1-alpha)*gamma; // going to presymptomatic
                     reulermultinom(2, E, rateE, dt, &dE_all);
                     double dEIa = dE_all[0];
                     double dEIp = dE_all[1];
                     double dIaR = rbinom(Ia, 1 - exp(-lambda_a*dt));
                     double rateIp[2];
                     double dIp_all[2];
                     rateIp[0] = mu*lambda_p; // going to mild symptomatic
                     rateIp[1] = (1-mu)*lambda_p; // going to severe symptomatic
                     reulermultinom(2, Ip, rateIp, dt, &dIp_all);
                     double dIpIm = dIp_all[0];
                     double dIpIs = dIp_all[1];
                     double dImR = rbinom(Im, 1 - exp(-lambda_m*dt));
                     
                     double rateIs[2];
                     double dIs_all[2];
                     rateIs[0] = delta*lambda_s; // hospitalized ultimately going to death
                     rateIs[1] = (1-delta)*lambda_s; // hospitalized ultimately going to recovered
                     reulermultinom(2, Is, rateIs, dt, &dIs_all);
                     double dIsHd = dIs_all[0];
                     double dIsHr = dIs_all[1];
                     double dHdD = rbinom(Hd, 1 - exp(-rho_d*dt));
                     double dHrR = rbinom(Hr, 1 - exp(-rho_r*dt));
                     
                     // update the compartments
                     S  -= dSE; // susceptible 
                     E  += dSE - dEIa - dEIp + import; // exposed
                     Ia += dEIa - dIaR; // infectious and asymptomatic
                     Ip += dEIp - dIpIs - dIpIm; // infectious and pre-symptomatic
                     Is += dIpIs - dIsHd - dIsHr; // infectious and severe symptoms (that will be hospitalized)
                     Im += dIpIm - dImR; // infectious and minor symptoms
                     I   = Ia + Ip + Im + Is; // total number of infected
                     I_new_sympt += dIpIs + dIpIm; // total number of newly symptomatic
                     Hr += dIsHr - dHrR; // hospitalized that will recover
                     Hd += dIsHd - dHdD; // hospitalizations that will die
                     H   = Hr + Hd; // total hospitalizations
                     R  += dHrR + dImR + dIaR; // recovered
                     D  += dHdD; // fatalities
                     D_new += dHdD; // daily fatalities
                     H_new += dIsHr + dIsHd; // daily new hospitalizations
                     ")

# define the initial set up, currently, every is susceptible except the exposed people
sir_init <- Csnippet("
                     double E0 = rpois(E_init);
                     S = N-E0;
                     E = E0;
                     Ia = 0;
                     Ip = 0;
                     Is = 0;
                     Im = 0;
                     I = 0;
                     I_new_sympt = 0;
                     Hr = 0;
                     Hd = 0;
                     H = Hd + Hr;
                     R = 0;
                     D = 0;
                     D_new = 0;
                     H_new = 0;
                     import_total = 0;
                     ")

# define random simulator of measurement
rmeas_deaths <- Csnippet("double tol = 1e-16;
                   deaths = rpois(D_new + tol);
                  ")
# define evaluation of model prob density function
dmeas_deaths <- Csnippet("double tol = 1e-16;
                   lik = dpois(deaths, D_new + tol, give_log);
                  ")

# define random simulator of measurement
rmeas_deaths_NB <- Csnippet("double tol = 1e-16;
                   deaths = rnbinom_mu(theta, D_new + tol);
                  ")
# define evaluation of model prob density function
dmeas_deaths_NB <- Csnippet("double tol = 1e-16;
                   lik = dnbinom_mu(deaths, theta, D_new + tol, give_log);
                  ")

# define random simulator of measurement
rmeas_hosp <- Csnippet("double tol = 1e-16;
                   hosp = rpois(H + tol);
                  ")
# define evaluation of model prob density function
dmeas_hosp <- Csnippet("double tol = 1e-16;
                   lik = dpois(hosp, H + tol, give_log);
                  ")

# define random simulator of measurement
rmeas_multi <- Csnippet("double tol = 1e-16;
                   double detect;
                   if (t < detect_t0) detect = 0;
                   else if (t >= detect_t0 & t <= detect_t1) {
                    detect = detect_max/detect_t1*(t - detect_t0);
                   } 
                   else  detect = detect_max; 
                   deaths = rnbinom_mu(theta_d, D_new + tol);
                   cases = rnbinom_mu(theta_c, detect*I_new_sympt + tol);
                  ")
# define evaluation of model prob density function
dmeas_multi <- Csnippet("double tol = 1e-16;
                   double detect;
                   if (t < detect_t0) detect = 0;
                   else if(t >= detect_t0 & t <= (detect_t0 + detect_t1)){
                    detect = detect_max/detect_t1*(t - detect_t0);
                   } 
                   else detect = detect_max; 
                   
                   if (ISNA(deaths)) {
                    lik = 0 + dnbinom_mu(cases, theta_c, detect*I_new_sympt + tol, 1);
                    //lik = (give_log) ? 0 : 1;
                   } else {
                    lik = dnbinom_mu(deaths, theta_d, D_new + tol, 1) + dnbinom_mu(cases, theta_c, detect*I_new_sympt + tol, 1);
                   }
                   lik = (give_log) ? lik : exp(lik);
                  ")

# parameters to transform
par_trans <- parameter_trans(log = c("beta0", "import_rate", "E_init", 
                                     "theta_d", "theta_c",
                                     "detect_t0", "detect_t1"),
                            logit = c("beta_min", "detect_max"))

param_names <- c(
   "beta0"
  , "Ca", "Cp", "Cs", "Cm"
  , "alpha"
  , "mu"
  , "delta"
  , "gamma"
  , "lambda_a", "lambda_s", "lambda_m", "lambda_p"
  , "rho_r"
  , "rho_d"
  , "N"
  # , "E0"
  , "E_init"
  # , "soc_dist_level_sip"
  , "import_rate"
  , "theta_d"
  , "theta_c"
  , "beta_min"
  , "detect_t0"
  , "detect_t1"
  , "detect_max"
)

# variables that should be zeroed after each obs
accum_names = c("D_new", "H_new", "I_new_sympt")

# state variables
state_names = c(
    "S" , "E" , "Ia"
  , "Ip", "Is", "Im"
  , "I" , "I_new_sympt"
  , "H" , "Hr", "Hd"
  , "R" , "D" 
  , "D_new", "H_new" 
  # , "thresh_crossed"
  , "import_total"
)


## R0 here just based on the simple transmission rate / recovery rate (weighted by the probability of going into different classes)
covid_R0 <- function (beta0est, fixed_params, sd_strength, prop_S) {
## transmission rate
 R <-   beta0est * prop_S * sd_strength * 
    (                
## proportion * time in asymptomatic
      fixed_params["alpha"] * fixed_params["Ca"] * (1/fixed_params["lambda_a"]) +                  
## proportion * time in mildly symptomatic
      (1 - fixed_params["alpha"]) * fixed_params["mu"] * ((1/fixed_params["lambda_p"]) + (1/fixed_params["lambda_m"])) +    
## proportion * time in severely symptomatic
      (1 - fixed_params["alpha"]) * (1 - fixed_params["mu"]) * ((1/fixed_params["lambda_p"]) + (1/fixed_params["lambda_s"]))      
      )
 
 unlist(R)
}


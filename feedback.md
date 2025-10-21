# Feedback

* Instructions didn't work on my laptop, M1 problems :(
* Starting from scratch, kubectl not installed. Used `minikube kubectl --` instead
* `make load` - Used 5GB of RAM which exceeded my EC2 instance. Can we slim down the image?
* `chmod +x` isn't privesc, script text says it is
* Tell me the commands before I press Enter to run them


NOTES:
##############################################################################
####               ERROR: You did not set a datadog.apiKey.               ####
##############################################################################

This deployment will be incomplete until you get your API key from Datadog.
One can sign up for a free Datadog trial at https://app.datadoghq.com/signup

Once registered you can request an API key at:

    https://app.datadoghq.com/account/settings#agent/kubernetes

Then run:

    helm upgrade datadog-agent \
        --set datadog.apiKey=YOUR-KEY-HERE stable/datadog

